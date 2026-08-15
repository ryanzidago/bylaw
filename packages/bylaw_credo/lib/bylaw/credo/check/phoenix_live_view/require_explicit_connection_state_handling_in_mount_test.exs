defmodule Bylaw.Credo.Check.PhoenixLiveView.RequireExplicitConnectionStateHandlingInMountTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.PhoenixLiveView.RequireExplicitConnectionStateHandlingInMount

  @message "Under LiveView's current lifecycle, mount/3 runs separately for the disconnected render and connected socket. Make mount/3 directly branch on connected?(socket), delegating to mount_connected/3 and mount_disconnected/3, so each operation runs in the intended state."

  test "reports a mount whose connected?/1 argument is a literal" do
    canonical_mount("connected?(nil)")
    |> source_file()
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> assert_issue()
  end

  test "reports a mount whose connected?/1 argument is another mount parameter" do
    canonical_mount("Phoenix.LiveView.connected?(session)")
    |> source_file()
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> assert_issue()
  end

  test "reports a mount whose connected?/1 argument is another bound variable" do
    """
    def mount(params, session, {socket, another_socket} = socket_pair) do
      if connected?(another_socket) do
        mount_connected(params, session, socket_pair)
      else
        mount_disconnected(params, session, socket_pair)
      end
    end
    """
    |> source_file()
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> assert_issue()
  end

  test "reports a mount parameter without a top-level forwarding binding" do
    """
    def mount(params, session, %{assigns: assigns}) do
      if connected?(assigns) do
        mount_connected(params, session, assigns)
      else
        mount_disconnected(params, session, assigns)
      end
    end
    """
    |> source_file()
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> assert_issue()
  end

  test "reports a connected handler whose forwarded arguments are reordered" do
    canonical_mount(
      "connected?(socket)",
      "mount_connected(socket, session, params)",
      "mount_disconnected(params, session, socket)"
    )
    |> source_file()
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> assert_issue()
  end

  test "reports a disconnected handler whose forwarded arguments are reordered or replaced with literals" do
    """
    #{canonical_mount("connected?(socket)",
    "mount_connected(params, session, socket)",
    "mount_disconnected(params, socket, session)")}

    def mount(params, session, socket) when is_map(params) do
      if connected?(socket) do
        mount_connected(params, session, socket)
      else
        mount_disconnected(:params, :session, :socket)
      end
    end
    """
    |> source_file()
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> assert_issues(2)
  end

  test "continues accepting correctly forwarded direct variables" do
    canonical_mount()
    |> source_file()
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> refute_issues()
  end

  test "continues accepting correctly forwarded variables extracted from pattern-matched guarded parameters" do
    """
    def mount(
          %{"id" => id} = params,
          %{"user" => user} = session,
          %{assigns: assigns} = socket
        )
        when is_binary(id) and is_map(assigns) and not is_nil(user) do
      #{canonical_if()}
    end
    """
    |> source_file()
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> refute_issues()
  end

  test "ignores a mount/3 function in a component-looking file" do
    invalid_mount = "def mount(_params, _session, socket), do: {:ok, socket}"

    for filename <- [
          "lib/example_web/components/profile_component.ex",
          "lib/example_web/live/profile_component.ex"
        ] do
      invalid_mount
      |> source_file(filename)
      |> run_check(RequireExplicitConnectionStateHandlingInMount)
      |> refute_issues()
    end
  end

  test "continues checking mount/3 in both live directories and _live.ex files" do
    invalid_mount = "def mount(_params, _session, socket), do: {:ok, socket}"

    invalid_mount
    |> source_file("lib/example_web/live/example.ex")
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> assert_issue()

    invalid_mount
    |> source_file("lib/example_web/example_live.ex")
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> assert_issue()
  end

  test "asserts the improved actionable diagnostic" do
    "def mount(_params, _session, socket), do: {:ok, socket}"
    |> source_file()
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> assert_issue(%{message: @message})
  end

  test "accepts the canonical connected and disconnected mount delegation" do
    canonical_mount()
    |> source_file()
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> refute_issues()

    """
    def mount(params, session, socket) do
      if connected?(socket),
        do: mount_connected(params, session, socket),
        else: mount_disconnected(params, session, socket)
    end
    """
    |> source_file()
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> refute_issues()
  end

  test "accepts qualified Phoenix.LiveView.connected?/1" do
    canonical_mount("Phoenix.LiveView.connected?(socket)")
    |> source_file()
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> refute_issues()
  end

  test "accepts arbitrary work inside both phase handlers" do
    """
    #{canonical_mount()}

    defp mount_connected(params, session, socket) do
      socket = subscribe_and_load(socket, params, session)
      {:ok, socket}
    end

    defp mount_disconnected(params, session, socket) do
      socket = query_and_compute(socket, params, session)
      {:ok, socket}
    end
    """
    |> source_file()
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> refute_issues()
  end

  test "reports an unbranched mount/3" do
    assert_invalid_mount("def mount(_params, _session, socket), do: {:ok, socket}")
  end

  test "reports merely calling connected?/1 without delegating through its branches" do
    assert_invalid_mount("""
    def mount(_params, _session, socket) do
      connected?(socket)
      {:ok, socket}
    end
    """)
  end

  test "reports work before the lifecycle branch" do
    assert_invalid_mount("""
    def mount(params, session, socket) do
      socket = assign(socket, :ready, true)
      #{canonical_if()}
    end
    """)
  end

  test "reports work after the lifecycle branch" do
    assert_invalid_mount("""
    def mount(params, session, socket) do
      #{canonical_if()}
      {:ok, socket}
    end
    """)
  end

  test "reports an if without an else branch" do
    assert_invalid_mount("""
    def mount(params, session, socket) do
      if connected?(socket), do: mount_connected(params, session, socket)
    end
    """)
  end

  test "reports reversed connected and disconnected handlers" do
    assert_invalid_mount("""
    def mount(params, session, socket) do
      if connected?(socket) do
        mount_disconnected(params, session, socket)
      else
        mount_connected(params, session, socket)
      end
    end
    """)
  end

  test "reports a connected branch that does not call mount_connected/3" do
    assert_invalid_mount(
      canonical_mount(
        "connected?(socket)",
        "{:ok, socket}",
        "mount_disconnected(params, session, socket)"
      )
    )
  end

  test "reports a disconnected branch that does not call mount_disconnected/3" do
    assert_invalid_mount(
      canonical_mount(
        "connected?(socket)",
        "mount_connected(params, session, socket)",
        "{:ok, socket}"
      )
    )
  end

  test "reports handler calls with the wrong arity" do
    assert_invalid_mount("""
    def mount(params, session, socket) do
      if connected?(socket) do
        mount_connected(socket)
      else
        mount_disconnected(params, session)
      end
    end
    """)
  end

  test "reports qualified handler calls" do
    assert_invalid_mount(
      canonical_mount(
        "connected?(socket)",
        "Helpers.mount_connected(params, session, socket)",
        "Helpers.mount_disconnected(params, session, socket)"
      )
    )
  end

  test "reports case unless and cond alternatives" do
    """
    def mount(params, session, socket) do
      case connected?(socket) do
        true -> mount_connected(params, session, socket)
        false -> mount_disconnected(params, session, socket)
      end
    end

    def mount(params, session, socket) when is_map(params) do
      unless connected?(socket) do
        mount_disconnected(params, session, socket)
      else
        mount_connected(params, session, socket)
      end
    end

    def mount(params, session, socket) when is_map(session) do
      cond do
        connected?(socket) -> mount_connected(params, session, socket)
        true -> mount_disconnected(params, session, socket)
      end
    end
    """
    |> source_file()
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> assert_issues(3)
  end

  test "reports combined connected conditions" do
    assert_invalid_mount(canonical_mount("connected?(socket) and ready?(socket)"))
  end

  test "accepts pattern-matched and guarded mount clauses when their bodies conform" do
    """
    def mount(%{"id" => id} = params, %{ "user" => user } = session, %{assigns: assigns} = socket)
        when is_binary(id) and is_map(assigns) and not is_nil(user) do
      #{canonical_if()}
    end
    """
    |> source_file()
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> refute_issues()
  end

  test "checks every mount/3 clause independently" do
    """
    #{canonical_mount()}

    def mount(_params, _session, socket) when is_map(socket), do: {:ok, socket}
    """
    |> source_file()
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> assert_issue(%{line_no: 11, trigger: "mount"})
  end

  test "reports one issue per invalid mount clause at the definition line" do
    """
    def mount(:first, _session, socket), do: {:ok, socket}

    def mount(:second, _session, socket) do
      load(socket)
    end
    """
    |> source_file()
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [2, 4]
      assert Enum.all?(issues, &(&1.trigger == "mount"))
      assert Enum.all?(issues, &(&1.message == @message))
    end)
  end

  test "ignores mount/1 LiveComponent callbacks" do
    "def mount(socket), do: {:ok, socket}"
    |> source_file("lib/example_web/live/profile_component.ex")
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> refute_issues()
  end

  test "ignores mount/3 outside LiveView-looking files" do
    "def mount(_params, _session, socket), do: {:ok, socket}"
    |> source_file("lib/example/worker.ex")
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> refute_issues()
  end

  test "does not crash on invalid source" do
    "defmodule Broken do\n  def mount("
    |> Credo.SourceFile.parse("lib/example_web/live/broken_live.ex")
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> refute_issues()
  end

  defp assert_invalid_mount(mount) do
    mount
    |> source_file()
    |> run_check(RequireExplicitConnectionStateHandlingInMount)
    |> assert_issue(%{line_no: 2, trigger: "mount", message: @message})
  end

  defp source_file(definitions, filename \\ "lib/example_web/live/example_live.ex") do
    to_source_file(
      """
      defmodule ExampleLive do
      #{definitions}
      end
      """,
      filename
    )
  end

  defp canonical_mount(
         condition \\ "connected?(socket)",
         connected \\ "mount_connected(params, session, socket)",
         disconnected \\ "mount_disconnected(params, session, socket)"
       ) do
    """
    def mount(params, session, socket) do
      if #{condition} do
        #{connected}
      else
        #{disconnected}
      end
    end
    """
  end

  defp canonical_if do
    """
    if connected?(socket) do
      mount_connected(params, session, socket)
    else
      mount_disconnected(params, session, socket)
    end
    """
  end
end
