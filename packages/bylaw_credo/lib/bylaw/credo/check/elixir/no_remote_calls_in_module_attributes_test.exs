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

  @doc """
  Issue: External function captures are reported with arity zero instead of their declared arity.
  Why it matters: The diagnostic points users to a function that may not exist and obscures the dependency being reported.
  """
  test "reports the declared arity for application function captures" do
    """
    defmodule Example do
      @some_function &MyApp.SomeModule.some_function/1
    end
    """
    |> to_source_file()
    |> run_check(NoRemoteCallsInModuleAttributes)
    |> assert_issue(%{
      line_no: 2,
      trigger: "MyApp.SomeModule.some_function",
      message: ~r/MyApp\.SomeModule\.some_function\/1/
    })
  end

  @doc """
  Issue: Nested module aliases rooted at `__MODULE__` crash while the check converts alias segments to strings.
  Why it matters: One valid module attribute can terminate the entire Credo run instead of returning a useful issue.
  """
  test "reports calls through nested modules rooted at __MODULE__ without crashing" do
    """
    defmodule Example do
      defmodule Nested do
        def values, do: []
      end

      @some_values __MODULE__.Nested.values()
    end
    """
    |> to_source_file()
    |> run_check(NoRemoteCallsInModuleAttributes)
    |> assert_issue(%{
      line_no: 6,
      trigger: "__MODULE__.Nested.values"
    })
  end

  @doc """
  Issue: An application alias whose short name matches a standard-library module is treated as standard library.
  Why it matters: Application compile-time dependencies can pass silently based only on the alias chosen by the caller.
  """
  test "reports application aliases that shadow standard-library module names" do
    """
    defmodule Example do
      alias MyApp.Enum

      @some_values Enum.values()
    end
    """
    |> to_source_file()
    |> run_check(NoRemoteCallsInModuleAttributes)
    |> assert_issue(%{
      line_no: 4,
      trigger: "Enum.values"
    })
  end

  @doc """
  Issue: A standard-library module renamed with `alias ... as:` is treated as an application module.
  Why it matters: Harmless standard-library calls produce false positives even though the default configuration permits them.
  """
  test "accepts renamed standard-library aliases by default" do
    """
    defmodule Example do
      alias Calendar.ISO, as: DateSystem

      @days DateSystem.days_in_era(1)
    end
    """
    |> to_source_file()
    |> run_check(NoRemoteCallsInModuleAttributes)
    |> refute_issues()
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

  @doc """
  Issue: The AST walker descends into valid quoted values and treats remote-call syntax as executed code.
  Why it matters: Macro and DSL modules receive false positives for calls that are stored as data and never run while defining the attribute.
  """
  test "ignores remote call syntax stored in quoted AST" do
    """
    defmodule Example do
      @quoted quote(do: MyApp.SomeModule.some_function())
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
