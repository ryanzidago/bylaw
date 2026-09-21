defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoComponentClassAttrTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.DesignSystem.NoComponentClassAttr

  @message "Give the component a named prop instead of a class attribute, so it owns its own styling."

  test "reports an attr named class" do
    """
    defmodule Example do
      attr :class, :any, default: nil

      def button(assigns) do
        ~H\"\"\"
        <button class={@class}>Save</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoComponentClassAttr)
    |> assert_issue(%{
      line_no: 2,
      trigger: "class",
      message: "#{@message} Component: <.button>."
    })
  end

  test "reports an attr whose name ends in class" do
    """
    defmodule Example do
      attr :wrapper_class, :string, default: nil

      def field(assigns) do
        ~H\"\"\"
        <div class={@wrapper_class}></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoComponentClassAttr)
    |> assert_issue(%{
      line_no: 2,
      trigger: "wrapper_class",
      message: "#{@message} Component: <.field>."
    })
  end

  test "reports the line, column and trigger of the attr declaration" do
    """
    defmodule Example do
      attr :label, :string, required: true
      attr :class, :any

      def button(assigns) do
        ~H\"\"\"
        <button class={@class}>{@label}</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoComponentClassAttr)
    |> assert_issue(%{line_no: 3, column: 9, trigger: "class"})
  end

  test "reports every class attr in a module" do
    """
    defmodule Example do
      attr :class, :any

      def button(assigns) do
        ~H\"\"\"
        <button class={@class}>Save</button>
        \"\"\"
      end

      attr :wrapper_class, :string

      def field(assigns) do
        ~H\"\"\"
        <div class={@wrapper_class}></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoComponentClassAttr)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 2, trigger: "class"},
      %{line_no: 10, trigger: "wrapper_class"}
    ])
  end

  test "reports a class attr declared for a private component" do
    """
    defmodule Example do
      attr :class, :any

      defp row(assigns) do
        ~H\"\"\"
        <div class={@class}></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoComponentClassAttr)
    |> assert_issue(%{line_no: 2, trigger: "class", message: "#{@message} Component: <.row>."})
  end

  test "reports a class attr that no definition follows" do
    """
    defmodule Example do
      attr :class, :any
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoComponentClassAttr)
    |> assert_issue(%{line_no: 2, trigger: "class", message: @message})
  end

  test "does not report other attrs" do
    """
    defmodule Example do
      attr :size, :string, values: ~w(md lg), default: "md"
      attr :variant, :string, values: ~w(primary danger)
      attr :classification, :atom
      attr :rest, :global

      def button(assigns) do
        ~H\"\"\"
        <button {@rest}>Save</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoComponentClassAttr)
    |> refute_issues()
  end

  test "does not report a slot named class" do
    """
    defmodule Example do
      slot :class

      def button(assigns) do
        ~H\"\"\"
        <button>{render_slot(@class)}</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoComponentClassAttr)
    |> refute_issues()
  end

  test "does not report components listed in excluded_components" do
    """
    defmodule Example do
      attr :class, :any, default: "size-4"

      def icon(assigns) do
        ~H\"\"\"
        <span class={@class} />
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoComponentClassAttr, excluded_components: [".icon"])
    |> refute_issues()
  end

  test "matches excluded components written with or without a leading dot" do
    """
    defmodule Example do
      attr :class, :any, default: "size-4"

      def icon(assigns) do
        ~H\"\"\"
        <span class={@class} />
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoComponentClassAttr, excluded_components: ["icon"])
    |> refute_issues()
  end

  test "reports components that are not listed in excluded_components" do
    """
    defmodule Example do
      attr :class, :any

      def icon(assigns) do
        ~H\"\"\"
        <span class={@class} />
        \"\"\"
      end

      attr :class, :any

      def button(assigns) do
        ~H\"\"\"
        <button class={@class}>Save</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoComponentClassAttr, excluded_components: [".icon"])
    |> assert_issue(%{line_no: 10, trigger: "class"})
  end

  test "does not report an attr call outside a module" do
    """
    attr :class, :any
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoComponentClassAttr)
    |> refute_issues()
  end

  test "does not crash on a module with no attrs" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="px-4">Profile</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoComponentClassAttr)
    |> refute_issues()
  end

  test "does not crash on an unparseable source" do
    "defmodule Example do\n  attr :class, :any"
    |> Credo.SourceFile.parse("lib/example.ex")
    |> run_check(NoComponentClassAttr)
    |> refute_issues()
  end
end
