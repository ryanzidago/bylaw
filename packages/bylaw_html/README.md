# Bylaw.HTML

Validate rendered HTML strings with explicit, composable checks.

`bylaw_html` works at the rendered HTML layer, not the source-template layer.
It parses the HTML string you already rendered, runs the checks you choose, and
returns `:ok` or `{:error, issues}` from `Bylaw.HTML.validate_html/2`.

In `0.1.0-alpha.1`, this package is core-only. It does not include Phoenix
adapters, test helper wrappers, default checks, or application config.

## Installation

Add `:bylaw_html` to your dependencies:

```elixir
def deps do
  [
    {:bylaw_html, "~> 0.1.0-alpha.1"}
  ]
end
```

## Usage

Choose the checks you want to run and pass them explicitly to
`Bylaw.HTML.validate_html/2`:

```elixir
checks = [
  Bylaw.HTML.Check.PreferLinkForNavigation
]

html = ~s(<a href="/settings">Settings</a>)

Bylaw.HTML.validate_html(html, checks)
```

`bylaw_html` does not read application config or register checks globally.
Callers choose checks explicitly each time.

## Built-in checks

Built-in checks live under `Bylaw.HTML.Check.*`.

`0.1.0-alpha.1` includes:

- `Bylaw.HTML.Check.PreferLinkForNavigation`

This first built-in check is intentionally narrow. It inspects rendered HTML
for non-`a` elements whose `phx-click` value is a JSON LiveView JS command
sequence containing `navigate` or `patch`.

## Why rendered HTML

Rendered HTML is a stable integration boundary for many test styles. It lets
you validate what the browser actually receives without coupling the check to
HEEx source, component internals, `%Phoenix.LiveView.JS{}` structs, or source
template conventions.

## Integration examples

These are example integration paths only. `bylaw_html` stays HTML-first and
plain-string based in `0.1.0-alpha.1`.

LiveView tests:

```elixir
html = render(view)
Bylaw.HTML.validate_html(html, checks)
```

Controller tests:

```elixir
html = html_response(conn, 200)
Bylaw.HTML.validate_html(html, checks)
```

Component tests:

```elixir
html = render_component(...)
Bylaw.HTML.validate_html(html, checks)
```

If you want assertion helpers, write a small downstream wrapper around
`Bylaw.HTML.validate_html/2` in your own test support, such as `ConnCase` or
LiveView test helpers.
