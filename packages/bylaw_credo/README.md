# Bylaw.Credo

Custom Credo checks.

## Installation

Downstream applications should typically include this package only in
development and test:

```elixir
{:bylaw_credo, "== 0.3.1", only: [:dev, :test], runtime: false}
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
        {Bylaw.Credo.Plugin.DisableForNextDefinition, []},
        {Bylaw.Credo.Plugin.HEExSources, []}
      ],
      checks: [
        {Bylaw.Credo.Check.Elixir.DocBeforeSpec, []},
        {Bylaw.Credo.Check.Elixir.NoRemoteCallsInModuleAttributes, []},
        {Bylaw.Credo.Check.Elixir.PreferEmptyListChecks, []},
        {Bylaw.Credo.Check.Elixir.SafeDateTimeComparison, []},
        {Bylaw.Credo.Check.HEEx.DesignSystem.NoArbitrarySpacing, []},
        {Bylaw.Credo.Check.Elixir.PreferBlockIf, []},
        {Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues, []},
        {Bylaw.Credo.Check.Ecto.NoDataChangesInSchemaMigrations, []},
        {Bylaw.Credo.Check.Ecto.PreferRepoOneOverAllFirst, []},
        {Bylaw.Credo.Check.Ecto.PreferOrderByOverRepoAllEnumSort, []},
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

## Function-level suppression

### What it solves

Credo's `disable-for-next-line` only suppresses an issue reported on the line
after the comment. It therefore cannot suppress a check that correctly reports
an issue several lines into a function. Making the check report the `def` line
would hide the real location, while `disable-for-lines:N` becomes wrong when
the function grows or shrinks.

`Bylaw.Credo.Plugin.DisableForNextDefinition` ties suppression to the next
function clause's AST range. Checks keep reporting the precise offending line,
and developers do not have to maintain line counts. Accurate locations matter
for editor navigation, explanations, reviews, and automated tooling.

### Installation

Add `bylaw_credo` to the application's development and test dependencies as
shown in [Installation](#installation), then enable the plugin in `.credo.exs`:

```elixir
%{
  configs: [
    %{
      name: "default",
      plugins: [
        {Bylaw.Credo.Plugin.DisableForNextDefinition, []}
      ]
    }
  ]
}
```

No changes to individual checks are required. The plugin works with Credo,
Bylaw, and third-party checks through Credo's standard issue filter.

### Usage

Name a check to suppress it throughout the next `def` or `defp` clause:

```elixir
# credo:disable-for-next-definition Bylaw.Credo.Check.Elixir.NoRaise
def run do
  perform_work()

  if failed?() do
    raise "failure"
  end
end
```

Omit the check to suppress all Credo issues in the definition:

```elixir
# credo:disable-for-next-definition
def generated_code do
  # ...
end
```

### Semantics and limits

- Blank lines and ordinary comments may separate the directive and definition.
- The range includes the `def` line through its matching `end`; one-line
  definitions and nested blocks are handled from token metadata.
- A directive before one clause of a multi-clause function applies only to that
  syntactic clause.
- The search does not cross module, protocol, implementation, or nested-module
  boundaries. Missing or inexact ranges suppress nothing.
- The first version supports `def` and `defp`, not macros, guards, delegates, or
  definitions inside `quote` blocks.
- The plugin runs for Credo's default Suggest command, List, and Diff.

`bylaw_credo` requires Credo `~> 1.7.16`. Credo 1.7.15 introduced the
token-annotated source AST needed for exact definition ranges, while 1.7.16 is
the first compatible release verified with this package's supported Elixir
versions. The plugin assumes the Credo 1.7 plugin pipelines and
`Credo.Check.ConfigComment` filtering contract remain available.

`Bylaw.Credo.Check.Elixir.SafeDateTimeComparison` reports direct comparisons of
values that look like dates or times and ignores comparisons inside Ecto query
expressions, where Ecto translates them into database predicates. Use the
relevant date/time module's comparison functions for ordinary Elixir values.

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

`Bylaw.Credo.Check.Ecto.PreferOrderByOverRepoAllEnumSort` reports direct
`Repo.all` results sorted in memory with `Enum.sort` or `Enum.sort_by`. Add
`order_by` to the Ecto query instead.

`Bylaw.Credo.Check.HEEx.PreferLinkForNavigation` enforces link semantics for
durable navigation. It reports explicit LiveView navigation commands wired
through `phx-click` on HEEx tags and components, so navigation uses real links
instead of click handlers on other elements.
