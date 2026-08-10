# Bylaw.Credo

Custom Credo checks.

## Installation

Downstream applications should typically include this package only in
development and test:

```elixir
{:bylaw_credo, "== 0.4.0", only: [:dev, :test], runtime: false}
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

See each check module's documentation for its examples, rationale, options, and
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
