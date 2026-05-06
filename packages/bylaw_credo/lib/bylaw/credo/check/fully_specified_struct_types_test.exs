defmodule Bylaw.Credo.Check.FullySpecifiedStructTypesTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.FullySpecifiedStructTypes

  test "reports empty struct literals in type declarations" do
    """
    defmodule Example do
      @type t :: %__MODULE__{}
      @typep wrapped :: {:ok, %URI{}}
      @opaque external :: list(%Date.Range{})
    end
    """
    |> to_source_file()
    |> run_check(FullySpecifiedStructTypes)
    |> assert_issues(3)
    |> assert_issues_match([
      %{line_no: 2, trigger: "%__MODULE__{}", message: ~r/Fully specify struct fields/},
      %{line_no: 3, trigger: "%URI{}", message: ~r/Fully specify struct fields/},
      %{line_no: 4, trigger: "%Date.Range{}", message: ~r/Fully specify struct fields/}
    ])
  end

  test "does not report fully specified struct fields, specs, or runtime structs" do
    """
    defmodule Example do
      defstruct [:id]

      @type t :: %__MODULE__{id: integer()}
      @opaque uri_t :: %URI{host: String.t() | nil}
      @spec build() :: %__MODULE__{}
      def build, do: %__MODULE__{}
    end
    """
    |> to_source_file()
    |> run_check(FullySpecifiedStructTypes)
    |> refute_issues()
  end
end
