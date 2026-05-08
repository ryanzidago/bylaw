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
      plugins: [
        {Bylaw.Credo.Plugin.HEExSources, []}
      ],
      checks: [
        {Bylaw.Credo.Check.Elixir.PreferEmptyListChecks, []},
        {Bylaw.Credo.Check.HEEx.RequireButtonType, []},
        {Bylaw.Credo.Check.HEEx.RequireImageAlt, []},
        {Bylaw.Credo.Check.HEEx.RequireLinkText, []},
        {Bylaw.Credo.Check.PreferListTypeSyntax, []}
      ]
    }
  ]
}
```

HEEx checks, including `Bylaw.Credo.Check.HEEx.RequireButtonType`,
`Bylaw.Credo.Check.HEEx.RequireImageAlt`, and
`Bylaw.Credo.Check.HEEx.RequireLinkText`, use Phoenix LiveView's HEEx tokenizer
when available. Add `phoenix_live_view` to applications that enable these
checks.

Credo discovers embedded `~H` templates in `.ex` and `.exs` files by default.
To check standalone Phoenix `.html.heex` templates, enable
`Bylaw.Credo.Plugin.HEExSources` as shown above.
