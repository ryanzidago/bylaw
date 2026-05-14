defmodule Bylaw.Credo.Check.HEEx.PreferComponentModuleTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.PreferComponentModule
  alias Bylaw.Credo.Plugin.HEExSources

  @button_rule [
    rules: [
      [
        prefer: [modules: [MyAppWeb.UI.Buttons]],
        when: [[html_tag: "button"]]
      ]
    ]
  ]

  test "reports inline HEEx tags matching html_tag" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="button">Save</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferComponentModule, @button_rule)
    |> assert_issue(%{
      line_no: 4,
      trigger: "<button",
      message: "Use MyAppWeb.UI.Buttons for this UI pattern instead of raw or local HEEx markup."
    })
  end

  test "reports matching tags inside local function components" do
    """
    defmodule Example do
      defp button(assigns) do
        ~H\"\"\"
        <button type="button"><%= @label %></button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferComponentModule, @button_rule)
    |> assert_issue(%{line_no: 4, trigger: "<button"})
  end

  test "does not report component calls" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.button type="button">Save</.button>
        <Buttons.button type="button">Save</Buttons.button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferComponentModule, @button_rule)
    |> refute_issues()
  end

  test "does not report raw markup inside the preferred module implementation" do
    """
    defmodule MyAppWeb.UI.Buttons do
      def button(assigns) do
        ~H\"\"\"
        <button type="button"><%= render_slot(@inner_block) %></button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/my_app_web/ui/buttons.ex")
    |> run_check(PreferComponentModule, @button_rule)
    |> refute_issues()
  end

  test "supports multiple preferred modules and exempts each implementation" do
    rule = [
      rules: [
        [
          prefer: [modules: [MyAppWeb.UI.Buttons, MyAppWeb.UI.IconButtons]],
          when: [[html_tag: "button"]]
        ]
      ]
    ]

    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="button">Save</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferComponentModule, rule)
    |> assert_issue(%{
      line_no: 4,
      trigger: "<button",
      message:
        "Use one of MyAppWeb.UI.Buttons, MyAppWeb.UI.IconButtons for this UI pattern instead of raw or local HEEx markup."
    })

    """
    defmodule MyAppWeb.UI.IconButtons do
      def icon_button(assigns) do
        ~H\"\"\"
        <button type="button"><%= render_slot(@inner_block) %></button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/my_app_web/ui/icon_buttons.ex")
    |> run_check(PreferComponentModule, rule)
    |> refute_issues()
  end

  test "still reports other rules inside a preferred module implementation" do
    rule = [
      rules: [
        [
          prefer: [modules: [MyAppWeb.UI.Buttons]],
          when: [[html_tag: "button"]]
        ],
        [
          prefer: [modules: [MyAppWeb.UI.Tables]],
          when: [[html_tag: "table"]]
        ]
      ]
    ]

    """
    defmodule MyAppWeb.UI.Buttons do
      def mixed(assigns) do
        ~H\"\"\"
        <button type="button">Allowed here</button>
        <table><tr><td>Still not a button concern</td></tr></table>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/my_app_web/ui/buttons.ex")
    |> run_check(PreferComponentModule, rule)
    |> assert_issue(%{line_no: 5, trigger: "<table"})
  end

  test "reports static attrs matching string values" do
    rule = [
      rules: [
        [
          prefer: [modules: [MyAppWeb.UI.Dropdowns]],
          when: [[attrs: [role: "menu"]]]
        ]
      ]
    ]

    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div role="menu">Actions</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferComponentModule, rule)
    |> assert_issue(%{
      line_no: 4,
      trigger: "<div",
      message:
        "Use MyAppWeb.UI.Dropdowns for this UI pattern instead of raw or local HEEx markup."
    })
  end

  test "reports attrs matching present values and dash-normalized atom keys" do
    rule = [
      rules: [
        [
          prefer: [modules: [MyAppWeb.UI.Links]],
          when: [[html_tag: "a", attrs: [phx_click: :present]]]
        ]
      ]
    ]

    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href="#" phx-click={@event}>Open</a>
        <button type="button" phx-click="save">Save</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferComponentModule, rule)
    |> assert_issue(%{line_no: 4, trigger: "<a"})
  end

  test "reports attrs matching regex values" do
    rule = [
      rules: [
        [
          prefer: [modules: [MyAppWeb.UI.Cards]],
          when: [[attrs: [class: ~r/\bcard\b/]]]
        ]
      ]
    ]

    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <section class="surface card">Billing</section>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferComponentModule, rule)
    |> assert_issue(%{line_no: 4, trigger: "<section"})
  end

  test "reports simple css_selector matches" do
    rule = [
      rules: [
        [
          prefer: [modules: [MyAppWeb.UI.Cards]],
          when: [[css_selector: "div.card"]]
        ]
      ]
    ]

    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="surface card">Billing</div>
        <section class="surface card">Billing</section>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferComponentModule, rule)
    |> assert_issue(%{line_no: 4, trigger: "<div"})
  end

  test "ors matchers in one rule" do
    rule = [
      rules: [
        [
          prefer: [modules: [MyAppWeb.UI.Tables]],
          when: [[html_tag: "table"], [attrs: [role: "table"]]]
        ]
      ]
    ]

    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <table><tr><td>Name</td></tr></table>
        <div role="table">Name</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferComponentModule, rule)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "<table"},
      %{line_no: 5, trigger: "<div"}
    ])
  end

  test "ands keys inside one matcher" do
    rule = [
      rules: [
        [
          prefer: [modules: [MyAppWeb.UI.Navigation]],
          when: [[html_tag: "a", attrs: [phx_click: :present]]]
        ]
      ]
    ]

    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href="/settings">Settings</a>
        <a href="#" phx-click="open">Open</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferComponentModule, rule)
    |> assert_issue(%{line_no: 5, trigger: "<a"})
  end

  test "reports regex matches against template source" do
    rule = [
      rules: [
        [
          prefer: [modules: [MyAppWeb.UI.Dropdowns]],
          when: [[regex: ~r/data-dropdown/]]
        ]
      ]
    ]

    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div data-dropdown>Actions</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferComponentModule, rule)
    |> assert_issue(%{line_no: 4, trigger: "data-dropdown"})
  end

  test "reports matching tags in html.heex files" do
    """
    <section>
      <button type="button">Save</button>
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(PreferComponentModule, @button_rule)
    |> assert_issue(%{line_no: 2, trigger: "<button"})
  end

  test "reports matching tags in html.heex files loaded by the Credo plugin" do
    tmp_dir = tmp_dir!("prefer-component-module")
    template_path = Path.join([tmp_dir, "lib", "example", "index.html.heex"])

    template_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(template_path, """
    <section>
      <button type="button">Save</button>
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
    |> run_check(PreferComponentModule, @button_rule)
    |> assert_issue(%{line_no: 2, trigger: "<button"})
  end

  test "raises for missing rules" do
    source_file =
      to_source_file(
        """
        defmodule Example do
          def render(assigns) do
            ~H\"\"\"
            <button type="button">Save</button>
            \"\"\"
          end
        end
        """,
        "lib/example.ex"
      )

    assert_raise ArgumentError,
                 "expected Elixir.Bylaw.Credo.Check.HEEx.PreferComponentModule :rules to be a non-empty list of rules",
                 fn ->
                   PreferComponentModule.run(source_file)
                 end
  end

  test "raises for malformed rules" do
    rule = [
      rules: [
        [
          prefer: [modules: [MyAppWeb.UI.Buttons]],
          when: [[unknown: "button"]]
        ]
      ]
    ]

    source_file =
      to_source_file(
        """
        defmodule Example do
          def render(assigns) do
            ~H\"\"\"
            <button type="button">Save</button>
            \"\"\"
          end
        end
        """,
        "lib/example.ex"
      )

    assert_raise ArgumentError,
                 "unknown Elixir.Bylaw.Credo.Check.HEEx.PreferComponentModule matcher option: :unknown",
                 fn ->
                   PreferComponentModule.run(source_file, rule)
                 end
  end

  test "raises when prefer does not declare modules" do
    rule = [
      rules: [
        [
          prefer: MyAppWeb.UI.Buttons,
          when: [[html_tag: "button"]]
        ]
      ]
    ]

    source_file =
      to_source_file(
        """
        defmodule Example do
          def render(assigns) do
            ~H\"\"\"
            <button type="button">Save</button>
            \"\"\"
          end
        end
        """,
        "lib/example.ex"
      )

    assert_raise ArgumentError,
                 "expected Elixir.Bylaw.Credo.Check.HEEx.PreferComponentModule rule :prefer to be [modules: [...]], got: MyAppWeb.UI.Buttons",
                 fn ->
                   PreferComponentModule.run(source_file, rule)
                 end
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

    File.rm_rf!(path)
    File.mkdir_p!(path)

    path
  end
end
