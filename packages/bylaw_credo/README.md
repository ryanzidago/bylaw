# Bylaw.Credo

Custom Credo checks.

## Installation

Downstream applications should typically include this package only in
development and test:

```elixir
{:bylaw_credo, "== 0.3.0", only: [:dev, :test], runtime: false}
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
        {Bylaw.Credo.Check.Elixir.DocBeforeSpec, []},
        {Bylaw.Credo.Check.Elixir.NoRemoteCallsInModuleAttributes, []},
        {Bylaw.Credo.Check.Elixir.PreferEmptyListChecks, []},
        {Bylaw.Credo.Check.HEEx.DesignSystem.NoArbitrarySpacing, []},
        {Bylaw.Credo.Check.Elixir.PreferBlockIf, []},
        {Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues, []},
        {Bylaw.Credo.Check.Ecto.NoDataChangesInSchemaMigrations, []},
        {Bylaw.Credo.Check.Ecto.PreferRepoOneOverAllFirst, []},
        {Bylaw.Credo.Check.HEEx.NoDuplicateStaticIds, []},
        {Bylaw.Credo.Check.HEEx.NoIndirectAssignAccess, []},
        {Bylaw.Credo.Check.HEEx.NoElementSpacing, []},
        {Bylaw.Credo.Check.HEEx.PreferNativeInteractiveElement, []},
        {Bylaw.Credo.Check.HEEx.PreferLinkForNavigation, []},
        {Bylaw.Credo.Check.HEEx.RequireAccessibleButtonText, []},
        {Bylaw.Credo.Check.HEEx.NoJavascriptHref, []},
        {Bylaw.Credo.Check.HEEx.RequireButtonType, []},
        {Bylaw.Credo.Check.HEEx.RequireImageAlt, []},
        {Bylaw.Credo.Check.HEEx.RequireLabelForInput, []},
        {Bylaw.Credo.Check.HEEx.RequireLoadingStateForSubmit, []},
        {Bylaw.Credo.Check.HEEx.RequireLinkHref, []},
        {Bylaw.Credo.Check.HEEx.RequireLinkText, []},
        {Bylaw.Credo.Check.HEEx.RequireTargetBlankRel, []},
        {Bylaw.Credo.Check.PhoenixLiveView.RequireFunctionComponentAttrs, []},
        {Bylaw.Credo.Check.Elixir.PreferListTypeSyntax, []},
        {Bylaw.Credo.Check.Testing.NoDescribeBlocks, []},
        {Bylaw.Credo.Check.Testing.PreferSelectorAssertionsForHtml, []}
      ]
    }
  ]
}
```

See each check module's documentation for its examples, notes, options, and
check-specific `.credo.exs` usage.

`Bylaw.Credo.Check.HEEx.NoIndirectAssignAccess` reports literal-key
`Map.get(assigns, key)` and `assigns[key]` access in HEEx templates. Initialize
assigns before rendering and access them directly with `@key` so missing values
and defaults are handled at the rendering boundary.

`Bylaw.Credo.Check.HEEx.DesignSystem.NoArbitrarySpacing` reports raw pixel
spacing values in static Tailwind classes and CSS margin or padding declarations.
Use design-system spacing tokens instead.

`Bylaw.Credo.Check.Elixir.NoRemoteCallsInModuleAttributes` reports calls into
application and dependency modules from module attributes because those calls
execute during compilation and embed their results in the consumer. Literal
values and Elixir or OTP standard-library calls are accepted by default.

`Bylaw.Credo.Check.Ecto.NoDataChangesInSchemaMigrations` reports direct Repo
row mutations and literal `INSERT`, `UPDATE`, `DELETE`, or `MERGE` SQL in Ecto
schema migrations. It is a best-effort guideline that points operational data
changes toward reviewed, resumable data-migration scripts or release tasks.

`Bylaw.Credo.Check.HEEx.PreferLinkForNavigation` enforces link semantics for
durable navigation. It reports explicit LiveView navigation commands wired
through `phx-click` on HEEx tags and components, so navigation uses real links
instead of click handlers on other elements.
