# Bylaw.Core

Shared core helpers for the Bylaw package family.

`bylaw_core` is the small core package used by packages such as `bylaw_db`,
`bylaw_ecto_query`, and `bylaw_postgres` to share validation result handling.
It does not currently expose consumer-facing modules.

## Installation

Most projects should depend on one of the domain packages instead of adding
`bylaw_core` directly. Add this package only when building another Bylaw package or
extension that needs the shared core helpers:

```elixir
def deps do
  [
    {:bylaw_core, "~> 0.1.0-alpha.1"}
  ]
end
```
