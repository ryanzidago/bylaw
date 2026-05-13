defmodule Bylaw.Credo.Check.HEEx.PreferLinkForNavigationTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.PreferLinkForNavigation
  alias Bylaw.Credo.Plugin.HEExSources

  @message "Use a link for navigation so users can open it in a new tab, copy the URL, and get native browser link behavior."

  test "reports JS.navigate in H sigils" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button phx-click={JS.navigate(~p"/settings")}>Settings</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferLinkForNavigation)
    |> assert_issue(%{
      line_no: 4,
      trigger: "<button",
      message: @message
    })
  end

  test "reports navigation on non-link native elements" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div phx-click={JS.patch(~p"/users")}>Users</div>
        <span phx-click={JS.navigate(~p"/reports")}>Reports</span>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferLinkForNavigation)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "<div", message: @message},
      %{line_no: 5, trigger: "<span", message: @message}
    ])
  end

  test "reports local and remote components used for explicit navigation" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.button phx-click={JS.navigate(~p"/settings")}>Settings</.button>
        <Button phx-click={Phoenix.LiveView.JS.patch("/users")} />
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferLinkForNavigation)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "<.button", message: @message},
      %{line_no: 5, trigger: "<Button", message: @message}
    ])
  end

  test "reports explicit navigation inside piped and wrapped JS expressions" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button phx-click={JS.navigate(~p"/settings") |> JS.dispatch("done")}>Settings</button>
        <div phx-click={wrap_navigation(JS.push("track") |> JS.patch(~p"/users"))}>Users</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferLinkForNavigation)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "<button", message: @message},
      %{line_no: 5, trigger: "<div", message: @message}
    ])
  end

  test "does not report link primitives used for navigation" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href={~p"/settings"} phx-click={JS.navigate(~p"/settings")}>Settings</a>
        <.link phx-click={Phoenix.LiveView.JS.patch("/users")}>Users</.link>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferLinkForNavigation)
    |> refute_issues()
  end

  test "does not report proper link semantics" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href={~p"/settings"}>Settings</a>
        <a href={~p"/users"} phx-click="track">Users</a>
        <.link navigate={~p"/billing"}>Billing</.link>
        <.link patch={~p"/profile"}>Profile</.link>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferLinkForNavigation)
    |> refute_issues()
  end

  test "does not report non-navigation click handlers" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="button" phx-click="save">Save</button>
        <button type="button" phx-click={JS.push("save")}>Save</button>
        <button type="submit">Submit</button>
        <.button phx-click={JS.push("cancel")}>Cancel</.button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferLinkForNavigation)
    |> refute_issues()
  end

  test "does not report ambiguous expressions without explicit navigation commands" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button phx-click={navigation_command(@path)}>Maybe</button>
        <div phx-click={@on_click}>Later</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferLinkForNavigation)
    |> refute_issues()
  end

  test "reports multiple navigation issues in html.heex files" do
    """
    <section>
      <button phx-click={JS.navigate(~p"/settings")}>Settings</button>
      <.button phx-click={JS.patch(~p"/users")}>Users</.button>
      <a href="/ok">Present</a>
      <span phx-click={Phoenix.LiveView.JS.navigate("/reports")}>Reports</span>
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(PreferLinkForNavigation)
    |> assert_issues(3)
    |> assert_issues_match([
      %{line_no: 2, trigger: "<button", message: @message},
      %{line_no: 3, trigger: "<.button", message: @message},
      %{line_no: 5, trigger: "<span", message: @message}
    ])
  end

  test "reports explicit navigation in html.heex files loaded by the Credo plugin" do
    tmp_dir = tmp_dir!("prefer-link-for-navigation")
    template_path = Path.join([tmp_dir, "lib", "example", "index.html.heex"])

    template_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(template_path, """
    <section>
      <Button phx-click={JS.navigate(~p"/settings")} />
      <.link navigate={~p"/users"}>Users</.link>
    </section>
    """)

    source_files =
      tmp_dir
      |> exec_for_tmp_project()
      |> HEExSources.LoadSourceFiles.call()
      |> Credo.Execution.get_source_files()

    assert [%Credo.SourceFile{filename: filename, status: :valid}] = source_files
    assert String.ends_with?(filename, "index.html.heex")

    source_files
    |> run_check(PreferLinkForNavigation)
    |> assert_issue(%{line_no: 2, trigger: "<Button", message: @message})
  end

  defp exec_for_tmp_project(tmp_dir) do
    %{
      Credo.Execution.build()
      | cli_options: %Credo.CLI.Options{path: tmp_dir},
        files: %{included: ["lib/**/*.{ex,exs}"], excluded: []}
    }
  end

  defp tmp_dir!(name) do
    path =
      Path.join(System.tmp_dir!(), "bylaw-credo-#{name}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    path
  end
end
