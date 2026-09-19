defmodule Bylaw.Credo.Check.Ecto.TypeBeforeSchemaTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Ecto.TypeBeforeSchema

  test "reports a @type that appears after the schema block" do
    """
    defmodule MyApp.User do
      use MyApp.Schema

      schema "users" do
        field :name, :string
      end

      @type t :: %__MODULE__{name: String.t() | nil}
    end
    """
    |> to_source_file()
    |> run_check(TypeBeforeSchema)
    |> assert_issue(fn issue ->
      assert issue.line_no == 8
      assert issue.trigger == "t"
    end)
  end

  test "reports a @type that appears after the embedded_schema block" do
    """
    defmodule MyApp.Address do
      use MyApp.Schema

      embedded_schema do
        field :city, :string
      end

      @type t :: %__MODULE__{city: String.t() | nil}
    end
    """
    |> to_source_file()
    |> run_check(TypeBeforeSchema)
    |> assert_issue()
  end

  test "reports every @type, @typep and @opaque after the schema block" do
    """
    defmodule MyApp.Label do
      use MyApp.Schema

      schema "labels" do
        field :color, Ecto.Enum, values: [:gray, :green]
      end

      @type color :: :gray | :green
      @typep name :: String.t()
      @opaque t :: %__MODULE__{color: color() | nil}
    end
    """
    |> to_source_file()
    |> run_check(TypeBeforeSchema)
    |> assert_issues(fn issues -> assert Enum.count(issues) == 3 end)
  end

  test "reports a @type after the schema even when functions sit between them" do
    """
    defmodule MyApp.User do
      use MyApp.Schema

      schema "users" do
        field :name, :string
      end

      def changeset(user, attrs), do: {user, attrs}

      @type t :: %__MODULE__{name: String.t() | nil}
    end
    """
    |> to_source_file()
    |> run_check(TypeBeforeSchema)
    |> assert_issue()
  end

  test "does not report a @type that appears before the schema block" do
    """
    defmodule MyApp.User do
      use MyApp.Schema

      @type t :: %__MODULE__{name: String.t() | nil}

      @primary_key false
      schema "users" do
        field :name, :string
      end

      def changeset(user, attrs), do: {user, attrs}
    end
    """
    |> to_source_file()
    |> run_check(TypeBeforeSchema)
    |> refute_issues()
  end

  test "does not report types in a module without a schema block" do
    """
    defmodule MyApp.Scope do
      defstruct [:user]

      def for_user(user), do: %__MODULE__{user: user}

      @type t :: %__MODULE__{user: term()}
    end
    """
    |> to_source_file()
    |> run_check(TypeBeforeSchema)
    |> refute_issues()
  end

  test "does not report types in a nested module that follows the outer schema" do
    """
    defmodule MyApp.User do
      use MyApp.Schema

      @type t :: %__MODULE__{name: String.t() | nil}

      schema "users" do
        field :name, :string
      end

      defmodule Settings do
        @type t :: %__MODULE__{theme: atom()}

        defstruct [:theme]
      end
    end
    """
    |> to_source_file()
    |> run_check(TypeBeforeSchema)
    |> refute_issues()
  end

  test "reports a @type after the schema block of a nested module" do
    """
    defmodule MyApp.Outer do
      defmodule Inner do
        use MyApp.Schema

        embedded_schema do
          field :name, :string
        end

        @type t :: %__MODULE__{name: String.t() | nil}
      end
    end
    """
    |> to_source_file()
    |> run_check(TypeBeforeSchema)
    |> assert_issue()
  end

  test "does not treat a function named schema as a schema block" do
    """
    defmodule MyApp.Api do
      def schema(name), do: name

      @type t :: map()
    end
    """
    |> to_source_file()
    |> run_check(TypeBeforeSchema)
    |> refute_issues()
  end
end
