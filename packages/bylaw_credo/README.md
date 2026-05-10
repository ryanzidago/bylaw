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

## Checks

### Elixir and typespecs

- `Bylaw.Credo.Check.DocBeforeSpec`
- `Bylaw.Credo.Check.FullySpecifiedStructTypes`
- `Bylaw.Credo.Check.FullyTypedOpts`
- `Bylaw.Credo.Check.NamedSpecParams`
- `Bylaw.Credo.Check.PreferListTypeSyntax`
- `Bylaw.Credo.Check.Elixir.AppModuleAcronymCasing`
- `Bylaw.Credo.Check.Elixir.FilterRejectFirst`
- `Bylaw.Credo.Check.Elixir.FloatUsage`
- `Bylaw.Credo.Check.Elixir.NoCatchAllInWithElse`
- `Bylaw.Credo.Check.Elixir.NoEndOfDayTime`
- `Bylaw.Credo.Check.Elixir.NoExtraPublicBehaviourFunctions`
- `Bylaw.Credo.Check.Elixir.NoLowLevelProcessPrimitives`
- `Bylaw.Credo.Check.Elixir.NoParamExtractionInFunctionHead`
- `Bylaw.Credo.Check.Elixir.NoPassthroughWrapper`
- `Bylaw.Credo.Check.Elixir.NoRaise`
- `Bylaw.Credo.Check.Elixir.NoResultTupleArgument`
- `Bylaw.Credo.Check.Elixir.NoThen`
- `Bylaw.Credo.Check.Elixir.NoTryRescue`
- `Bylaw.Credo.Check.Elixir.PreferEmptyListChecks`
- `Bylaw.Credo.Check.Elixir.PreferEnumCount`
- `Bylaw.Credo.Check.Elixir.PreferEnumUniqBy`
- `Bylaw.Credo.Check.Elixir.RejectCount`
- `Bylaw.Credo.Check.Elixir.SafeDateTimeComparison`
- `Bylaw.Credo.Check.Elixir.UseMaybeInFunctionName`
- `Bylaw.Credo.Check.Elixir.WithElseClause`

#### Minimal behaviour implementations

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

### Ecto

- `Bylaw.Credo.Check.Ecto.ComposablePreloadQueries`
- `Bylaw.Credo.Check.Ecto.ErrorChangesetPatternMatch`
- `Bylaw.Credo.Check.Ecto.NamedBinding`
- `Bylaw.Credo.Check.Ecto.NoAndInWhere`
- `Bylaw.Credo.Check.Ecto.NoRepoPreloadAfterQuery`
- `Bylaw.Credo.Check.Ecto.NoRepoTransaction`
- `Bylaw.Credo.Check.Ecto.OwnContextForSchema`
- `Bylaw.Credo.Check.Ecto.PipeBasedQueries`
- `Bylaw.Credo.Check.Ecto.PreferDateTimeOverDate`
- `Bylaw.Credo.Check.Ecto.PreferRepoAggregateCount`
- `Bylaw.Credo.Check.Ecto.PreferSelectOverRepoAllEnumMap`
- `Bylaw.Credo.Check.Ecto.UseBylawSchema`

### HEEx

- `Bylaw.Credo.Check.HEEx.NoDuplicateStaticIds`
- `Bylaw.Credo.Check.HEEx.NoElementSpacing`
- `Bylaw.Credo.Check.HEEx.NoJavascriptHref`
- `Bylaw.Credo.Check.HEEx.PreferNativeInteractiveElement`
- `Bylaw.Credo.Check.HEEx.RequireAccessibleButtonText`
- `Bylaw.Credo.Check.HEEx.RequireButtonType`
- `Bylaw.Credo.Check.HEEx.RequireImageAlt`
- `Bylaw.Credo.Check.HEEx.RequireLabelForInput`
- `Bylaw.Credo.Check.HEEx.RequireLinkHref`
- `Bylaw.Credo.Check.HEEx.RequireLinkText`
- `Bylaw.Credo.Check.HEEx.RequireLoadingStateForSubmit`
- `Bylaw.Credo.Check.HEEx.RequireTargetBlankRel`

### Phoenix

- `Bylaw.Credo.Check.Phoenix.ContextFunctionNaming`
- `Bylaw.Credo.Check.Phoenix.NoRepoInController`
- `Bylaw.Credo.Check.Phoenix.URIDecodeQuery`
- `Bylaw.Credo.Check.Phoenix.UseVerifiedRoutes`
- `Bylaw.Credo.Check.PhoenixLiveView.NoInlineAssignInReturnTuple`

### Testing

- `Bylaw.Credo.Check.Testing.NoGlobalStateInTests`
- `Bylaw.Credo.Check.Testing.NoSetupInTests`
- `Bylaw.Credo.Check.Testing.NoTestsInTestDir`

## HEEx templates

HEEx checks use Phoenix LiveView's undocumented HEEx tokenizer when it is
available. Add `phoenix_live_view` to applications that enable these checks.

Credo discovers embedded `~H` templates in `.ex` and `.exs` files by default.
To check standalone Phoenix `.html.heex` templates, enable
`Bylaw.Credo.Plugin.HEExSources` as shown above.

See each check module's documentation for its examples, notes, options, and
check-specific `.credo.exs` usage.
