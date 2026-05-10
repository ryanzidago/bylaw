# Bylaw.Credo

Custom Credo checks.

## Installation

Downstream applications should typically include this package only in
development and test:

```elixir
{:bylaw_credo, "~> 0.1.0", only: [:dev, :test], runtime: false}
```

## Usage

Configure Bylaw Credo checks through Credo's normal `.credo.exs` API. Add each
check you want by listing its fully qualified module in the `checks:` list:

```elixir
%{
  configs: [
    %{
      name: "default",
      plugins: [
        {Bylaw.Credo.Plugin.HEExSources, []}
      ],
      checks: [
        {Bylaw.Credo.Check.DocBeforeSpec, []},
        {Bylaw.Credo.Check.Elixir.PreferEmptyListChecks, []},
        {Bylaw.Credo.Check.HEEx.NoDuplicateStaticIds, []},
        {Bylaw.Credo.Check.HEEx.NoElementSpacing, []},
        {Bylaw.Credo.Check.HEEx.PreferNativeInteractiveElement, []},
        {Bylaw.Credo.Check.HEEx.RequireAccessibleButtonText, []},
        {Bylaw.Credo.Check.HEEx.NoJavascriptHref, []},
        {Bylaw.Credo.Check.HEEx.RequireButtonType, []},
        {Bylaw.Credo.Check.HEEx.RequireImageAlt, []},
        {Bylaw.Credo.Check.HEEx.RequireLabelForInput, []},
        {Bylaw.Credo.Check.HEEx.RequireLoadingStateForSubmit, []},
        {Bylaw.Credo.Check.HEEx.RequireLinkHref, []},
        {Bylaw.Credo.Check.HEEx.RequireLinkText, []},
        {Bylaw.Credo.Check.HEEx.RequireTargetBlankRel, []},
        {Bylaw.Credo.Check.PreferListTypeSyntax, []}
      ]
    }
  ]
}
```

There is no separate Bylaw runtime validation API for these checks. Credo loads
the check modules from `.credo.exs` and passes each check its configured option
list.

## Minimal behaviour implementations

`Bylaw.Credo.Check.Elixir.NoExtraPublicBehaviourFunctions` is opt-in by
behaviour. Configure `:behaviours` with the behaviour modules whose
implementations should keep a minimal public API:

```elixir
{Bylaw.Credo.Check.Elixir.NoExtraPublicBehaviourFunctions,
 [
   behaviours: [
     Bylaw.Db.Check,
     Bylaw.Ecto.Query.Check
   ],
   allowed: []
 ]}
```

The check reads callback signatures from each configured behaviour module with
`behaviour_info(:callbacks)`, so callback lists should not be duplicated in
Credo config. Use `:allowed`, for example `[child_spec: 1]`, for intentional
extra public functions.

## HEEx templates

HEEx checks use Phoenix LiveView's undocumented HEEx tokenizer when it is
available. Add `phoenix_live_view` to applications that enable these checks.

Credo discovers embedded `~H` templates in `.ex` and `.exs` files by default.
To check standalone Phoenix `.html.heex` templates, enable
`Bylaw.Credo.Plugin.HEExSources` as shown above.

See each check module's documentation for its examples, notes, options, and
check-specific `.credo.exs` usage.
