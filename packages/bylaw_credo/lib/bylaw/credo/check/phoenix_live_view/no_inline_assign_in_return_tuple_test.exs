defmodule Bylaw.Credo.Check.PhoenixLiveView.NoInlineAssignInReturnTupleTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.PhoenixLiveView.NoInlineAssignInReturnTuple

  defp live_view_code(return_tuple, filename \\ "lib/bylaw_web/live/example_live.ex") do
    code = """
    defmodule ExampleLive do
      use Phoenix.LiveView

      def mount(_params, _session, socket) do
        #{return_tuple}
      end
    end
    """

    to_source_file(code, filename)
  end

  test "reports inline assign in {:ok, ...}" do
    "{:ok, assign(socket, :foo, :bar)}"
    |> live_view_code()
    |> run_check(NoInlineAssignInReturnTuple)
    |> assert_issue()
  end

  test "reports piped assign in {:noreply, ...}" do
    "{:noreply, socket |> assign(:foo, :bar)}"
    |> live_view_code()
    |> run_check(NoInlineAssignInReturnTuple)
    |> assert_issue()
  end

  test "does not report plain socket tuples" do
    """
    defmodule ExampleLive do
      use Phoenix.LiveView

      def mount(_params, _session, socket) do
        socket = assign(socket, :foo, :bar)
        {:ok, socket}
      end
    end
    """
    |> to_source_file("lib/bylaw_web/live/example_live.ex")
    |> run_check(NoInlineAssignInReturnTuple)
    |> refute_issues()
  end

  test "does not report non-liveview files" do
    "{:ok, assign(socket, :foo, :bar)}"
    |> live_view_code("lib/bylaw/example.ex")
    |> run_check(NoInlineAssignInReturnTuple)
    |> refute_issues()
  end
end
