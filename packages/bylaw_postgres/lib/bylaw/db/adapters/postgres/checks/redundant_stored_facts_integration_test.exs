defmodule Bylaw.Db.Adapters.Postgres.Checks.RedundantStoredFactsIntegrationTest do
  use ExUnit.Case, async: false

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.RedundantStoredFacts
  alias Bylaw.Db.Postgres.TestDatabase
  alias Bylaw.Db.Postgres.TestRepo
  alias Ecto.Adapters.SQL.Sandbox

  @moduletag :postgres
  @schema "bylaw_redundant_facts"

  setup do
    TestDatabase.start_repo!()
    owner = Sandbox.start_owner!(TestRepo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    TestDatabase.query!("CREATE SCHEMA #{@schema}")
    %{target: Postgres.target(repo: TestRepo)}
  end

  test "captures actual Offer-like catalogue evidence and changes after dropping the duplicate discriminator",
       %{target: target} do
    TestDatabase.query!("CREATE TYPE #{@schema}.offer_scope AS ENUM ('menu', 'item')")
    TestDatabase.query!("CREATE TABLE #{@schema}.menus (id bigint PRIMARY KEY)")
    TestDatabase.query!("CREATE TABLE #{@schema}.items (id bigint PRIMARY KEY)")

    TestDatabase.query!("""
    CREATE TABLE #{@schema}.offers (
      id bigint PRIMARY KEY,
      applies_to #{@schema}.offer_scope NOT NULL,
      menu_id bigint REFERENCES #{@schema}.menus(id),
      item_id bigint REFERENCES #{@schema}.items(id),
      unit_price numeric NOT NULL,
      CONSTRAINT one_target CHECK ((menu_id IS NULL) <> (item_id IS NULL))
    )
    """)

    before = capture(target, "offers")

    assert Enum.map(before.table.columns, & &1.name) == [
             "id",
             "applies_to",
             "menu_id",
             "item_id",
             "unit_price"
           ]

    assert Enum.find(before.table.columns, &(&1.name == "applies_to")).type_details.enum_labels ==
             ["menu", "item"]

    assert Enum.count(before.table.constraints, &(&1.kind == "f")) == 2

    assert Enum.any?(
             before.table.constraints,
             &(&1.name == "one_target" and &1.definition =~ "CHECK")
           )

    assert Enum.any?(before.table.indexes, &(&1.definition =~ "UNIQUE INDEX"))

    TestDatabase.query!("ALTER TABLE #{@schema}.offers DROP COLUMN applies_to")
    after_drop = capture(target, "offers")
    refute Enum.any?(after_drop.table.columns, &(&1.name == "applies_to"))

    assert Enum.map(after_drop.table.columns, & &1.name) == [
             "id",
             "menu_id",
             "item_id",
             "unit_price"
           ]

    assert before.table != after_drop.table
  end

  test "preserves full definitions comments generated identity domain enum and partitioned table evidence",
       %{target: target} do
    TestDatabase.query!(
      "CREATE DOMAIN #{@schema}.price AS numeric(12,2) DEFAULT 1 NOT NULL CHECK (VALUE >= 0)"
    )

    TestDatabase.query!("""
    CREATE TABLE #{@schema}.facts (
      id bigint GENERATED ALWAYS AS IDENTITY,
      price #{@schema}.price,
      quantity integer NOT NULL DEFAULT 2,
      total numeric GENERATED ALWAYS AS (price * quantity) STORED
    ) PARTITION BY RANGE (id)
    """)

    TestDatabase.query!(
      "ALTER TABLE #{@schema}.facts ADD CONSTRAINT nonnegative CHECK (quantity >= 0) NOT VALID"
    )

    TestDatabase.query!("COMMENT ON TABLE #{@schema}.facts IS 'Quoted table meaning'")
    TestDatabase.query!("COMMENT ON COLUMN #{@schema}.facts.price IS 'Agreed price'")
    long_expression = Enum.map_join(1..180, " || ", fn _ -> "'long'::text" end)
    TestDatabase.query!("CREATE INDEX long_definition ON #{@schema}.facts ((#{long_expression}))")

    input = capture(target, "facts")
    assert input.table.kind == "partitioned"
    assert input.table.comment == "Quoted table meaning"
    [id, price, quantity, total] = input.table.columns
    assert id.identity == "a"
    assert price.comment == "Agreed price"
    assert price.type_details.kind == "domain"
    assert price.type_details.base_type == "numeric(12,2)"
    assert price.type_details.nullable == false
    assert Enum.any?(price.type_details.constraints, &(&1.definition =~ "VALUE"))
    assert quantity.default == "2"
    assert total.default == nil
    assert total.generated_kind == "s"
    assert total.generated_expression =~ "price"

    assert Enum.any?(
             input.table.constraints,
             &(&1.name == "nonnegative" and &1.validated == false)
           )

    assert Enum.any?(input.table.indexes, &(byte_size(&1.definition) > 1000))
  end

  test "identifies cross schema foreign key targets independently of search_path", %{
    target: target
  } do
    TestDatabase.query!("CREATE SCHEMA #{@schema}_reference")
    TestDatabase.query!("CREATE TABLE #{@schema}_reference.items (id bigint PRIMARY KEY)")
    TestDatabase.query!("CREATE TABLE #{@schema}.items (id bigint PRIMARY KEY)")

    TestDatabase.query!(
      "CREATE TABLE #{@schema}.offers (item_id bigint REFERENCES #{@schema}_reference.items(id))"
    )

    input = capture(target, "offers")
    assert [constraint] = input.table.constraints
    assert constraint.referenced_table == %{schema: "#{@schema}_reference", name: "items"}
  end

  defp capture(target, table) do
    parent = self()

    assert :ok =
             RedundantStoredFacts.validate(target,
               reviewer: fn input ->
                 send(parent, {:review_input, input})
                 {:ok, :no_violation}
               end,
               rules: [where: [schemas: [@schema], tables: [table]]]
             )

    assert_received {:review_input, input}
    refute_received {:review_input, _}
    input
  end
end
