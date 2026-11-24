defmodule Bylaw.Credo.Check.Elixir.BooleanFieldsIsPrefixTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.BooleanFieldsIsPrefix

  test "reports a schema field without the prefix, with options and in an embedded schema" do
    """
    defmodule Sample do
      use Ecto.Schema

      schema "options" do
        field :active, :boolean
        field :is_active, :boolean
        field :is_popular, :boolean, default: false
        field :name, :string
      end
    end

    defmodule Form do
      use Ecto.Schema

      embedded_schema do
        field :timed, :boolean
      end
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(BooleanFieldsIsPrefix)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.trigger}) == [
               {5, "active"},
               {16, "timed"}
             ]

      assert hd(issues).message =~ "is_active"
    end)
  end

  test "reports a migration column without the prefix" do
    """
    defmodule Sample.Migration do
      def change do
        create table(:options) do
          add :active, :boolean, null: false, default: true
          add :is_active, :boolean, null: false
          add :name, :text
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/sample.exs")
    |> run_check(BooleanFieldsIsPrefix)
    |> assert_issue(fn issue ->
      assert {issue.line_no, issue.trigger} == {4, "active"}
    end)
  end

  test "reports a map and struct key typed boolean in a typespec" do
    """
    defmodule Sample do
      @type settings :: %{active: boolean(), name: String.t()}
      @type form :: %__MODULE__{active: boolean() | nil, optional: boolean()}
      @type other :: %{is_active: boolean(), count: integer()}
      @spec enabled?(settings :: map()) :: boolean()
      @spec build(name :: String.t()) :: {:ok, map()} | {:error, term()}
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(BooleanFieldsIsPrefix)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.trigger}) == [
               {2, "active"},
               {3, "active"},
               {3, "optional"}
             ]
    end)
  end

  test "reports an OpenApiSpex boolean property" do
    """
    defmodule Sample.Schemas do
      alias OpenApiSpex.Schema

      def properties do
        %{
          active: %Schema{type: :boolean, description: "Active"},
          is_active: %Schema{type: :boolean},
          name: %Schema{type: :string},
          count: %OpenApiSpex.Schema{type: :integer},
          deep: %{active: %Schema{type: :boolean}}
        }
      end
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(BooleanFieldsIsPrefix)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.trigger}) == [
               {5, "active"},
               {10, "active"}
             ]
    end)
  end

  test "does not report arrays, variables, non-literal types or prefixed fields" do
    """
    defmodule Sample do
      use Ecto.Schema

      schema "options" do
        field :tags, {:array, :boolean}
        field :flag, var
        field :typed, {:parameterized, Ecto.Enum}
        field :is_flag, :boolean
        field :name, :string
      end

      @spec cast(map()) :: %{optional(atom()) => boolean()}
      @spec any?(list()) :: boolean()
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(BooleanFieldsIsPrefix)
    |> refute_issues()
  end

  test "honours allowed_prefixes" do
    """
    defmodule Sample do
      use Ecto.Schema

      schema "options" do
        field :has_flag, :boolean
        field :active, :boolean
      end
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(BooleanFieldsIsPrefix, allowed_prefixes: ["has_"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "active"
      assert issue.message =~ "is_active"
    end)
  end
end
