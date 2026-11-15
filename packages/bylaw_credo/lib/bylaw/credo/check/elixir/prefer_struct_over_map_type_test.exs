defmodule Bylaw.Credo.Check.Elixir.PreferStructOverMapTypeTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.PreferStructOverMapType

  test "reports a closed map type with literal atom keys in a type declaration" do
    """
    defmodule Example do
      @type user :: %{id: integer(), name: String.t()}
      @typep row :: %{:id => integer(), required(:name) => String.t()}
      @opaque token :: %{:value => String.t(), optional(:expires_at) => DateTime.t()}
    end
    """
    |> to_source_file()
    |> run_check(PreferStructOverMapType)
    |> assert_issues(3)
    |> assert_issues_match([
      %{line_no: 2, trigger: "%{id: integer(), name: String.t()}", message: ~r/@enforce_keys/},
      %{line_no: 3, message: ~r/Prefer a struct/},
      %{line_no: 4, message: ~r/t\(\)/}
    ])
  end

  test "does not report a closed map type below min_keys" do
    """
    defmodule Example do
      @type wrapper :: %{value: integer()}
      @type empty :: %{}
    end
    """
    |> to_source_file()
    |> run_check(PreferStructOverMapType)
    |> refute_issues()
  end

  test "honours a custom min_keys" do
    source = """
    defmodule Example do
      @type pair :: %{left: integer(), right: integer()}
      @type triple :: %{a: integer(), b: integer(), c: integer()}
    end
    """

    source
    |> to_source_file()
    |> run_check(PreferStructOverMapType, min_keys: 3)
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)

    source
    |> to_source_file()
    |> run_check(PreferStructOverMapType, min_keys: 1)
    |> assert_issues(2)
  end

  test "does not report open map types with non-literal keys" do
    """
    defmodule Example do
      @type attrs :: %{optional(atom()) => term()}
      @type counts :: %{String.t() => integer()}
      @type mixed :: %{:id => integer(), :name => String.t(), optional(atom()) => term()}
      @type params :: %{required(String.t()) => String.t(), optional(:page) => integer()}
    end
    """
    |> to_source_file()
    |> run_check(PreferStructOverMapType)
    |> refute_issues()
  end

  test "reports closed map types inline in spec and callback arguments and returns" do
    """
    defmodule Example do
      @callback fetch(id :: integer()) :: {:ok, %{id: integer(), name: String.t()}} | :error

      @spec rename(user :: %{id: integer(), name: String.t()}, name :: String.t()) :: :ok
      def rename(_user, _name), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(PreferStructOverMapType)
    |> assert_issues(2)
    |> assert_issues_match([%{line_no: 2}, %{line_no: 4}])
  end

  test "does not report struct types" do
    """
    defmodule Example do
      @enforce_keys [:id, :name]
      defstruct [:id, :name]

      @type t :: %__MODULE__{id: integer(), name: String.t()}
      @type uri :: %URI{host: String.t(), path: String.t()}
      @spec build() :: %__MODULE__{}
      def build, do: %__MODULE__{id: 1, name: "a"}
    end
    """
    |> to_source_file()
    |> run_check(PreferStructOverMapType)
    |> refute_issues()
  end

  test "reports closed map types nested in struct fields and other types" do
    """
    defmodule Example do
      @type t :: %__MODULE__{meta: %{source: String.t(), at: DateTime.t()}}
      @type rows :: list(%{id: integer(), name: String.t()})
    end
    """
    |> to_source_file()
    |> run_check(PreferStructOverMapType)
    |> assert_issues(2)
  end

  test "does not report map literals outside typespecs" do
    """
    defmodule Example do
      @defaults %{id: 1, name: "a"}

      def build, do: %{id: 1, name: "a"}
      def match(%{id: id, name: name}), do: {id, name}
    end
    """
    |> to_source_file()
    |> run_check(PreferStructOverMapType)
    |> refute_issues()
  end

  test "respects excluded paths" do
    source = """
    defmodule Example do
      @type user :: %{id: integer(), name: String.t()}
    end
    """

    source
    |> to_source_file("lib/generated/example.ex")
    |> run_check(PreferStructOverMapType, excluded_paths: ["lib/generated/"])
    |> refute_issues()

    source
    |> to_source_file("lib/generated/example.ex")
    |> run_check(PreferStructOverMapType, excluded_paths: [~r"/generated/"])
    |> refute_issues()
  end
end
