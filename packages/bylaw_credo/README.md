# Bylaw.Credo

Custom Credo checks for Bylaw.

Downstream applications should typically include this package only in
development and test:

```elixir
{:bylaw_credo, path: "../bylaw_credo", only: [:dev, :test], runtime: false}
```
