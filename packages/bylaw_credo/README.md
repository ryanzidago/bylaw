# Bylaw.Credo

Custom Credo checks for Bylaw.

Downstream applications should typically include this package only in
development and test:

```elixir
{:bylaw_credo, "~> 0.1.0", only: [:dev, :test], runtime: false}
```

Then enable the checks you want in your Credo configuration:

```elixir
%{
  configs: [
    %{
      name: "default",
      checks: [
        {Bylaw.Credo.Check.Elixir.PreferEmptyListChecks, []},
        {Bylaw.Credo.Check.PreferListTypeSyntax, []}
      ]
    }
  ]
}
```

`Bylaw.Credo.Check.RequireImageAlt` uses Phoenix LiveView's HEEx tokenizer when
available. Add `phoenix_live_view` to applications that enable this check.
