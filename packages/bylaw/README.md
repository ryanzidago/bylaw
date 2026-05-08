# Bylaw

Internal shared helpers for the Bylaw package family.

`bylaw` is the small core package used by packages such as `bylaw_db`,
`bylaw_ecto_query`, and `bylaw_postgres` to share validation result handling.
It does not currently expose consumer-facing modules.

## Installation

Most projects should depend on one of the domain packages instead of adding
`bylaw` directly. Add this package only when building another Bylaw package or
extension that needs the shared core helpers:

```elixir
def deps do
  [
    {:bylaw, "~> 0.1.0"}
  ]
end
```
