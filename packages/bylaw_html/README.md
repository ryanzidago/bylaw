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
    Bylaw.HTML.Check.RequireImageAlt
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

`bylaw_html` does not read application config or register checks globally.

## Built-in checks

Built-in checks live under `Bylaw.HTML.Check.*`.

`0.1.0-alpha.1` includes:

- `Bylaw.HTML.Check.PreferLinkForNavigation`
- `Bylaw.HTML.Check.PreferButtonForAction`
- `Bylaw.HTML.Check.RequireImageAlt`
- `Bylaw.HTML.Check.RequireLinkHref`

Start with the checks that match your application invariants; each check module
documents its own examples, notes, options, and copyable check specs.

## Why rendered HTML

Rendered HTML is a stable integration boundary for many test styles. It lets
you validate what the browser actually receives without coupling the check to
HEEx source, component internals, `%Phoenix.LiveView.JS{}` structs, or source
template conventions.

Rendered HTML validation reports the offending markup snippet, not the source
component or template that produced it.
