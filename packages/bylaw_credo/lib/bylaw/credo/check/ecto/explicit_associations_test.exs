defmodule Bylaw.Credo.Check.Ecto.ExplicitAssociationsTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Ecto.ExplicitAssociations

  test "reports persisted foreign-key fields without belongs_to" do
    issues =
      """
      defmodule Example.Order do
        use Ecto.Schema

        schema "orders" do
          field :organisation_id, :binary_id
          field :location_id, Ecto.UUID
          field :status, Ecto.Enum, values: [:open, :closed]
        end
      end
      """
      |> to_source_file("lib/example/order.ex")
      |> run_check(ExplicitAssociations)
      |> assert_issues(2)

    assert Enum.map(issues, & &1.trigger) == ["organisation_id", "location_id"]
    assert Enum.all?(issues, &(&1.message =~ "belongs_to"))
  end

  test "ignores virtual fields, embedded schemas, embeds, and non-schema structs" do
    """
    defmodule Example.Form do
      use Ecto.Schema

      embedded_schema do
        field :customer_id, :binary_id
      end
    end

    defmodule Example.Order do
      use Ecto.Schema

      schema "orders" do
        field :external_id, :string, virtual: true
        embeds_one :form, Example.Form do
          field :customer_id, :binary_id
        end
      end
    end

    defmodule Example.Plain do
      defstruct [:customer_id]
    end
    """
    |> to_source_file("lib/example/form.ex")
    |> run_check(ExplicitAssociations)
    |> refute_issues()
  end

  test "ignores primary keys and fields declared by belongs_to" do
    """
    defmodule Example.User do
      use Ecto.Schema
      @primary_key false

      schema "users" do
        field :account_id, :binary_id, primary_key: true
        belongs_to :organisation, Example.Organisation
      end
    end
    """
    |> to_source_file("lib/example/user.ex")
    |> run_check(ExplicitAssociations)
    |> refute_issues()
  end

  test "recognizes separately declared foreign keys with define_field false in either order" do
    """
    defmodule Example.First do
      use Ecto.Schema

      schema "firsts" do
        field :organisation_id, :binary_id
        belongs_to :organisation, Example.Organisation, define_field: false
      end
    end

    defmodule Example.Second do
      use Ecto.Schema

      schema "seconds" do
        belongs_to :organisation, Example.Organisation, define_field: false
        field :organisation_id, :binary_id
      end
    end
    """
    |> to_source_file("lib/example/memberships.ex")
    |> run_check(ExplicitAssociations)
    |> refute_issues()
  end

  test "recognizes a belongs_to foreign_key option" do
    """
    defmodule Example.Membership do
      use Ecto.Schema

      schema "memberships" do
        field :org_id, :binary_id
        belongs_to :organisation, Example.Organisation,
          foreign_key: :org_id,
          define_field: false
      end
    end
    """
    |> to_source_file("lib/example/membership.ex")
    |> run_check(ExplicitAssociations)
    |> refute_issues()
  end

  test "honors virtual false and virtual true explicitly" do
    """
    defmodule Example.Order do
      use Ecto.Schema
      @virtual true
      @is_primary_key true

      schema "orders" do
        field :real_owner_id, :binary_id, virtual: false
        field :ui_owner_id, :binary_id, virtual: true
        field :maybe_virtual_id, :binary_id, virtual: @virtual
        field :maybe_primary_key_id, :binary_id, primary_key: @is_primary_key
      end
    end
    """
    |> to_source_file("lib/example/order.ex")
    |> run_check(ExplicitAssociations)
    |> assert_issues(3)
    |> assert_issues_match([
      %{trigger: "real_owner_id"},
      %{trigger: "maybe_virtual_id"},
      %{trigger: "maybe_primary_key_id"}
    ])
  end

  test "honors a primary key field override" do
    """
    defmodule Example.Join do
      use Ecto.Schema
      @primary_key {:join_id, :binary_id, autogenerate: true}

      schema "joins" do
        field :owner_id, :binary_id
      end
    end
    """
    |> to_source_file("lib/example/join.ex")
    |> run_check(ExplicitAssociations)
    |> assert_issues(1)
    |> assert_issues_match([%{trigger: "owner_id"}])
  end

  test "checks schemas independently when a file has multiple schema blocks" do
    """
    defmodule Example.Record do
      use Ecto.Schema

      schema "records" do
        field :external_id, :binary_id
        belongs_to :owner, Example.User
      end

      schema "archive_records" do
        field :import_id, :binary_id
      end
    end
    """
    |> to_source_file("lib/example/record.ex")
    |> run_check(ExplicitAssociations)
    |> assert_issues(2)
  end

  test "allows narrowly scoped module and field exemptions" do
    issues =
      """
      defmodule Example.External do
        use Ecto.Schema

        schema "externals" do
          field :provider_id, :string
        end
      end

      defmodule Example.Container do
        defmodule External do
          use Ecto.Schema

          schema "nested_externals" do
            field :provider_id, :string
          end
        end
      end

      defmodule Example.Internal do
        use Ecto.Schema

        schema "internals" do
          field :provider_id, :binary_id
        end
      end
      """
      |> to_source_file("lib/example/external.ex")
      |> run_check(ExplicitAssociations,
        ignore: [{Example.External, :provider_id}]
      )
      |> assert_issues(2)

    assert Enum.map(issues, & &1.scope) == ["Example.Container.External", "Example.Internal"]
  end

  test "resolves nested module names when applying scoped exemptions" do
    """
    defmodule Example.Container do
      defmodule External do
        use Ecto.Schema

        schema "nested_externals" do
          field :provider_id, :string
        end
      end
    end

    defmodule Example.Internal do
      use Ecto.Schema

      schema "internals" do
        field :provider_id, :binary_id
      end
    end
    """
    |> to_source_file("lib/example/container.ex")
    |> run_check(ExplicitAssociations,
      ignore: [{Example.Container.External, :provider_id}]
    )
    |> assert_issues(1)
    |> assert_issues_match([%{trigger: "provider_id", scope: "Example.Internal"}])
  end
end
