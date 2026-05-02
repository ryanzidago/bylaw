defmodule Bylaw.Credo.Check.Design.NoPassthroughWrapperTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Design.NoPassthroughWrapper

  test "reports private local passthrough wrappers" do
    """
    defmodule Example do
      def call(value), do: format_datetime(value)

      defp format_datetime(value), do: DateTime.to_iso8601(value)
    end
    """
    |> to_source_file()
    |> run_check(NoPassthroughWrapper)
    |> assert_issue(%{
      line_no: 4,
      trigger: "format_datetime",
      message: ~r/forwards arguments to `DateTime.to_iso8601\/1`/
    })
  end

  test "reports piped passthrough wrappers" do
    """
    defmodule Example do
      def call(value), do: normalize(value)

      defp normalize(value), do: value |> String.trim()
    end
    """
    |> to_source_file()
    |> run_check(NoPassthroughWrapper)
    |> assert_issue(%{
      line_no: 4,
      trigger: "normalize",
      message: ~r/forwards arguments to `String.trim\/1`/
    })
  end

  test "reports passthrough wrappers with a simple match binding" do
    """
    defmodule Example do
      def call(value), do: format_datetime(value)

      defp format_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
    end
    """
    |> to_source_file()
    |> run_check(NoPassthroughWrapper)
    |> assert_issue(%{
      line_no: 4,
      trigger: "format_datetime"
    })
  end

  test "does not report dynamic delegation wrappers" do
    """
    defmodule Example do
      def call(opts), do: list(opts)

      defp list(opts), do: impl().list(opts)
    end
    """
    |> to_source_file()
    |> run_check(NoPassthroughWrapper)
    |> refute_issues()
  end

  test "does not report public wrappers by default" do
    """
    defmodule Example do
      def format_datetime(value), do: DateTime.to_iso8601(value)
    end
    """
    |> to_source_file()
    |> run_check(NoPassthroughWrapper)
    |> refute_issues()
  end

  test "reports public wrappers when configured" do
    """
    defmodule Example do
      def format_datetime(value), do: DateTime.to_iso8601(value)
    end
    """
    |> to_source_file()
    |> run_check(NoPassthroughWrapper, include_public: true)
    |> assert_issue(%{
      line_no: 2,
      trigger: "format_datetime"
    })
  end

  test "does not report wrappers that transform arguments" do
    """
    defmodule Example do
      def call(value), do: normalize(value)

      defp normalize(value), do: String.trim(value, " ")
    end
    """
    |> to_source_file()
    |> run_check(NoPassthroughWrapper)
    |> refute_issues()
  end

  test "does not report a single passthrough clause inside a multi-clause function" do
    """
    defmodule Example do
      def format_datetime(nil), do: nil
      def format_datetime(value), do: DateTime.to_iso8601(value)
    end
    """
    |> to_source_file()
    |> run_check(NoPassthroughWrapper, include_public: true)
    |> refute_issues()
  end

  test "does not report guarded definitions" do
    """
    defmodule Example do
      def call(value), do: stringify(value)

      defp stringify(value) when is_binary(value), do: to_string(value)
    end
    """
    |> to_source_file()
    |> run_check(NoPassthroughWrapper)
    |> refute_issues()
  end
end
