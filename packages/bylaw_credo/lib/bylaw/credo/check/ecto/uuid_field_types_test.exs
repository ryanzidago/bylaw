defmodule Bylaw.Credo.Check.Ecto.UUIDFieldTypesTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Ecto.UUIDFieldTypes

  test "rejects broad and local alias types for actual UUID fields" do
    for type <- [
          "String.t()",
          "binary()",
          "any()",
          "term()",
          "identifier()",
          "Ecto.UUID.t() | String.t()"
        ] do
      source(
        "@type identifier :: String.t()\n@type t :: %__MODULE__{id: #{type}}",
        "@primary_key {:id, :binary_id, []}",
        ""
      )
      |> to_source_file()
      |> run_check(UUIDFieldTypes)
      |> assert_issue(fn issue -> assert issue.trigger == "id" end)
    end
  end

  test "accepts UUID aliases and nil unions while preserving natural and external strings" do
    source(
      "alias Ecto.UUID, as: Identifier\n@type t :: %__MODULE__{id: Identifier.t() | nil, code: String.t(), external_id: String.t()}",
      "@primary_key {:id, Ecto.UUID, []}",
      "field :code, :string\nfield :external_id, :string"
    )
    |> to_source_file()
    |> run_check(UUIDFieldTypes)
    |> refute_issues()
  end

  test "uses explicit primary keys and belongs_to defaults and overrides" do
    source(
      "@type t :: %__MODULE__{id: Ecto.UUID.t(), owner_id: String.t(), manager_id: String.t(), provider_id: String.t()}",
      "@primary_key {:id, :binary_id, []}\n@foreign_key_type :binary_id",
      "belongs_to :owner, Example.Owner\nbelongs_to :manager, Example.Owner, type: Ecto.UUID\nbelongs_to :provider, Example.Provider, type: :string"
    )
    |> to_source_file()
    |> run_check(UUIDFieldTypes)
    |> assert_issues(2)
  end

  test "checks embedded schemas and isolates nested modules" do
    """
    defmodule Example.Form do
      use Ecto.Schema
      @type t :: %__MODULE__{id: String.t(), code: String.t()}
      embedded_schema do
        field :code, :string
      end
      defmodule Plain do
        defstruct [:id]
        @type t :: %__MODULE__{id: String.t()}
      end
    end
    """
    |> to_source_file()
    |> run_check(UUIDFieldTypes)
    |> assert_issues(1)
  end

  test "does not infer primary key defaults from custom schema wrappers" do
    source("@type t :: %__MODULE__{id: String.t()}", "", "")
    |> String.replace("use Ecto.Schema", "use Example.Schema")
    |> to_source_file()
    |> run_check(UUIDFieldTypes)
    |> refute_issues()
  end

  test "resolves grouped aliases and explicit fields without inventing associations" do
    source(
      "alias Ecto.{UUID}\n@type t :: %__MODULE__{id: UUID.t(), parent_id: term(), token: binary(), external_id: String.t()}",
      "@primary_key {:id, UUID, []}",
      "field :parent_id, UUID, primary_key: true\nfield :token, :binary_id, virtual: true\nbelongs_to :external, Example.External, define_field: false, type: :binary_id"
    )
    |> to_source_file()
    |> run_check(UUIDFieldTypes)
    |> assert_issues(2)
  end

  test "rejects missing UUID fields and imprecise branches of struct unions" do
    source(
      "@type t :: %__MODULE__{id: Ecto.UUID.t()} | %__MODULE__{id: nil}",
      "@primary_key {:id, Ecto.UUID, []}",
      "field :owner_id, :binary_id"
    )
    |> to_source_file()
    |> run_check(UUIDFieldTypes)
    |> assert_issues(2)
  end

  test "uses lexical alias scopes for declarations before and after a schema" do
    source(
      "alias Ecto.UUID, as: Identifier\n@type t :: %__MODULE__{id: Identifier.t()}",
      "@primary_key {:id, Identifier, []}",
      ""
    )
    |> String.replace("\nend\n", "\n  alias String, as: Identifier\nend\n")
    |> to_source_file()
    |> run_check(UUIDFieldTypes)
    |> refute_issues()
  end

  defp source(types, attributes, fields) do
    """
    defmodule Example.Record do
      use Ecto.Schema
      #{types}
      #{attributes}
      schema "records" do
        #{fields}
      end
    end
    """
  end
end
