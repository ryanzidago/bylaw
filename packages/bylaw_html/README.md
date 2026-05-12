# Bylaw.HTML

Validate rendered HTML strings before assertions finish, so invalid HTML
patterns are easier to catch and harder to ship.

Use `bylaw_html` to enforce application-specific HTML invariants, keep rendered
markup accessible and semantically correct, and codify conventions around links,
buttons, images, and other browser-facing behavior. Callers choose checks
explicitly and pass them to `Bylaw.HTML.validate_html/2`.

## Installation

Add `:bylaw_html` to test dependencies:

```elixir
def deps do
  [
    {:bylaw_html, "~> 0.1.0-alpha.1", only: :test}
  ]
end
```

## Usage

Choose the checks you want to enforce and pass them explicitly to
`Bylaw.HTML.validate_html/2` from your tests:

```elixir
defmodule MyAppWeb.PageHTMLTest do
  use MyAppWeb.ConnCase, async: true

  @html_checks [
    Bylaw.HTML.Check.RequireLinkHref,
    Bylaw.HTML.Check.PreferButtonForAction,
    Bylaw.HTML.Check.PreferLinkForNavigation,
    Bylaw.HTML.Check.RequireImageAlt,
    Bylaw.HTML.Check.NoInlineStyle
  ]

  test "home page satisfies Bylaw HTML checks", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert :ok = Bylaw.HTML.validate_html(html, @html_checks)
  end
end
```

For LiveView and component tests, pass the rendered string from the test helper:

```elixir
html = render(view)
assert :ok = Bylaw.HTML.validate_html(html, @html_checks)
```

```elixir
html = render_component(&MyAppWeb.Button.button/1, label: "Save")
assert :ok = Bylaw.HTML.validate_html(html, @html_checks)
```

If you want assertion helpers, write a small downstream wrapper around
`Bylaw.HTML.validate_html/2` in your own test support, such as `ConnCase` or
LiveView test helpers.

For example, in `test/support/html_assertions.ex`:

```elixir
defmodule MyAppWeb.HTMLAssertions do
  import ExUnit.Assertions

  @html_checks [
    Bylaw.HTML.Check.RequireLinkHref,
    Bylaw.HTML.Check.PreferButtonForAction,
    Bylaw.HTML.Check.PreferLinkForNavigation,
    Bylaw.HTML.Check.RequireImageAlt,
    Bylaw.HTML.Check.NoInlineStyle
  ]

  def assert_valid_html(html) when is_binary(html) do
    case Bylaw.HTML.validate_html(html, @html_checks) do
      :ok ->
        html

      {:error, issues} ->
        flunk(format_html_issues(issues))
    end
  end

  defp format_html_issues(issues) do
    issues
    |> Enum.map_join("\n\n", fn issue ->
      [issue.message, issue.snippet]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")
    end)
  end
end
```

Then import it from your case template:

```elixir
defmodule MyAppWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import MyAppWeb.HTMLAssertions
    end
  end
end
```

And use it in tests:

```elixir
html =
  conn
  |> get(~p"/")
  |> html_response(200)

assert_valid_html(html)
```

`bylaw_html` does not read application config or register checks globally.
