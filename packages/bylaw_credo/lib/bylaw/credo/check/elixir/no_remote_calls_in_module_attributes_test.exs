defmodule Bylaw.Credo.Check.Elixir.NoRemoteCallsInModuleAttributesTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.NoRemoteCallsInModuleAttributes

  test "reports application remote calls in custom module attributes" do
    """
    defmodule Example do
      @some_values MyApp.SomeModule.some_function()

      def some_values, do: @some_values
    end
    """
    |> to_source_file()
    |> run_check(NoRemoteCallsInModuleAttributes)
    |> assert_issue(%{
      line_no: 2,
      trigger: "MyApp.SomeModule.some_function",
      message: ~r/compile-time dependency/
    })
  end

  test "reports application remote calls nested inside allowed standard-library calls" do
    """
    defmodule Example do
      @some_values Enum.map(MyApp.SomeModule.some_values(), &to_string/1)
    end
    """
    |> to_source_file()
    |> run_check(NoRemoteCallsInModuleAttributes)
    |> assert_issue(%{
      line_no: 2,
      trigger: "MyApp.SomeModule.some_values"
    })
  end

  test "reports application function captures stored in module attributes" do
    """
    defmodule Example do
      @some_function &MyApp.SomeModule.some_function/1
    end
    """
    |> to_source_file()
    |> run_check(NoRemoteCallsInModuleAttributes)
    |> assert_issue(%{
      line_no: 2,
      trigger: "MyApp.SomeModule.some_function"
    })
  end

  test "accepts literal values in custom module attributes" do
    """
    defmodule Example do
      @some_values [:one, %{two: {3, "four"}}]
      @some_module MyApp.SomeModule
      @some_number 42
    end
    """
    |> to_source_file()
    |> run_check(NoRemoteCallsInModuleAttributes)
    |> refute_issues()
  end

  test "accepts Elixir and OTP standard-library calls by default" do
    """
    defmodule Example do
      @enum_values Enum.uniq([1, 1])
      @explicit_elixir_values Elixir.Enum.uniq([1, 1])
      @map_value Map.new([answer: 42])
      @kernel_value Kernel.to_string(:ok)
      @erlang_value :maps.from_list([{:answer, 42}])
    end
    """
    |> to_source_file()
    |> run_check(NoRemoteCallsInModuleAttributes)
    |> refute_issues()
  end

  test "reports standard-library calls when the standard-library allowance is disabled" do
    """
    defmodule Example do
      @some_values Enum.uniq([1, 1])
    end
    """
    |> to_source_file()
    |> run_check(NoRemoteCallsInModuleAttributes, allow_standard_library: false)
    |> assert_issue(%{
      line_no: 2,
      trigger: "Enum.uniq"
    })
  end

  test "ignores remote-call-shaped typespecs" do
    """
    defmodule Example do
      @type result :: {:ok, String.t()} | {:error, MyApp.Error.t()}
      @spec call(URI.t()) :: result()
    end
    """
    |> to_source_file()
    |> run_check(NoRemoteCallsInModuleAttributes, allow_standard_library: false)
    |> refute_issues()
  end

  test "ignores remote call syntax stored in quoted AST" do
    """
    defmodule Example do
      @quoted quote do
        MyApp.SomeModule.some_function()
      end
    end
    """
    |> to_source_file()
    |> run_check(NoRemoteCallsInModuleAttributes)
    |> refute_issues()
  end

  test "ignores remote calls made inside functions" do
    """
    defmodule Example do
      def some_values, do: MyApp.SomeModule.some_function()
    end
    """
    |> to_source_file()
    |> run_check(NoRemoteCallsInModuleAttributes)
    |> refute_issues()
  end
end
