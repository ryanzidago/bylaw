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
        {Bylaw.Credo.Check.Elixir.NoComments, []},
        {Bylaw.Credo.Check.Elixir.NoRemoteCallsInModuleAttributes, []},
        {Bylaw.Credo.Check.Elixir.NetworkOnlyInIntegrations, []},
        {Bylaw.Credo.Check.Elixir.PreferEmptyListChecks, []},
        {Bylaw.Credo.Check.Elixir.PreferStructOverMapType, []},
        {Bylaw.Credo.Check.HEEx.DesignSystem.NoArbitrarySpacing, []},
        {Bylaw.Credo.Check.HEEx.DesignSystem.NoArbitraryValues, []},
        {Bylaw.Credo.Check.HEEx.DesignSystem.NoComponentClass, []},
        {Bylaw.Credo.Check.HEEx.DesignSystem.NoComponentClassAttr, []},
        {Bylaw.Credo.Check.HEEx.DesignSystem.NoElementStyling,
         [files: %{excluded: ["lib/my_app_web/components/"]}]},
        {Bylaw.Credo.Check.HEEx.DesignSystem.NoHexColor, []},
        {Bylaw.Credo.Check.HEEx.DesignSystem.NoInlineStyle, []},
        {Bylaw.Credo.Check.HEEx.DesignSystem.PreferComponentOverTag,
         [tags: [button: ".button", input: ".input"], files: %{excluded: ["lib/my_app_web/components/"]}]},
        {Bylaw.Credo.Check.Elixir.PreferBlockIf, []},
        {Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues, []},
        {Bylaw.Credo.Check.Ecto.NoDataChangesInSchemaMigrations, []},
        {Bylaw.Credo.Check.Ecto.ExplicitAssociations, []},
        {Bylaw.Credo.Check.Ecto.PreferRepoOneOverAllFirst, []},
        {Bylaw.Credo.Check.Ecto.PreferOrderByOverRepoAllEnumSort, []},
        {Bylaw.Credo.Check.Ecto.TypeBeforeSchema, []},
        {Bylaw.Credo.Check.Ecto.UUIDFieldTypes, []},
        {Bylaw.Credo.Check.Ecto.UseTimestamptzInMigrations, []},
        {Bylaw.Credo.Check.Ecto.UtcDatetimeUsecInSchemas, []},
        {Bylaw.Credo.Check.HEEx.NoDuplicateStaticIds, []},
        {Bylaw.Credo.Check.HEEx.NoIndirectAssignAccess, []},
        {Bylaw.Credo.Check.HEEx.NoElementSpacing, []},
        {Bylaw.Credo.Check.HEEx.PreferNativeInteractiveElement, []},
        {Bylaw.Credo.Check.HEEx.PreferLinkForNavigation, []},
        {Bylaw.Credo.Check.HEEx.RequireAccessibleButtonText, []},
        {Bylaw.Credo.Check.HEEx.NoJavascriptHref, []},
        {Bylaw.Credo.Check.HEEx.NoRawSVG, []},
        {Bylaw.Credo.Check.HEEx.RequireButtonType, []},
        {Bylaw.Credo.Check.HEEx.RequireFormFieldIdOrName, []},
        {Bylaw.Credo.Check.HEEx.RequireImageAlt, []},
        {Bylaw.Credo.Check.HEEx.RequireLabelForInput, []},
        {Bylaw.Credo.Check.HEEx.RequireLoadingStateForSubmit, []},
        {Bylaw.Credo.Check.HEEx.RequireLinkHref, []},
        {Bylaw.Credo.Check.HEEx.RequireLinkText, []},
        {Bylaw.Credo.Check.HEEx.RequireTargetBlankRel, []},
        {Bylaw.Credo.Check.HEEx.NoUntranslatedText, []},
        {Bylaw.Credo.Check.Phoenix.NoRepoInWeb, []},
        {Bylaw.Credo.Check.PhoenixLiveView.RequireExplicitConnectionStateHandlingInMount, []},
        {Bylaw.Credo.Check.PhoenixLiveView.RequireFunctionComponentAttrs, []},
        {Bylaw.Credo.Check.Elixir.PreferListTypeSyntax, []},
        {Bylaw.Credo.Check.Testing.NoDescribeBlocks, []},
        {Bylaw.Credo.Check.Testing.HTTPStubsOnlyInClientTests, []},
        {Bylaw.Credo.Check.Testing.NoSleepInTests, []},
        {Bylaw.Credo.Check.Testing.NoUnseededRandomness, []},
        {Bylaw.Credo.Check.Testing.NoGlobalStateInAsyncTests, []},
        {Bylaw.Credo.Check.Testing.NoLiteralReceiveTimeout, []},
        {Bylaw.Credo.Check.Elixir.NoWallClock, [allowed_modules: [MyApp.Clock]]},
        {Bylaw.Credo.Check.Testing.PreferSelectorAssertionsForHtml, []},
        {Bylaw.Credo.Check.Testing.RequireAsyncTests, []}
      ]
    }
  ]
}
```

See each check module's documentation for its examples, rationale, options, and
check-specific `.credo.exs` usage.

`ExplicitAssociations` reports persisted `*_id` fields in `schema` blocks
without a matching `belongs_to`. For intentional external identifiers, scope
an exception to the schema and field:

```elixir
{Bylaw.Credo.Check.Ecto.ExplicitAssociations,
 [ignore: [{MyApp.ExternalRecord, :provider_id}]]}
```

## Companion to Bylaw.Contract

[Bylaw.Contract](https://hexdocs.pm/bylaw_contract/readme.html) measures which
spec-derived cases tests exercise. Credo's built-in
[`Specs`](https://hexdocs.pm/credo/Credo.Check.Readability.Specs.html) check
requires specs to exist (`include_defp: true` includes private functions).

Bylaw's
[`NamedSpecParams`](https://hexdocs.pm/bylaw_credo/Bylaw.Credo.Check.Elixir.NamedSpecParams.html),
[`FullyTypedOpts`](https://hexdocs.pm/bylaw_credo/Bylaw.Credo.Check.Elixir.FullyTypedOpts.html), and
[`FullySpecifiedStructTypes`](https://hexdocs.pm/bylaw_credo/Bylaw.Credo.Check.Elixir.FullySpecifiedStructTypes.html)
checks help make specs explicit.

`FullySpecifiedStructTypes` rejects empty literals in source. To require a
public `t/0` and every field for **all** application structs, run the compiled
struct audit after compilation in a test or QA script:

```elixir
modules = Application.spec(:my_app, :modules)
sources = Path.wildcard("lib/**/*.ex")
:ok = Bylaw.Credo.StructTypes.validate(modules, sources)
```

For Ecto schemas, `UUIDFieldTypes` requires explicit `Ecto.UUID.t()` (optionally
unioned with `nil`) for fields declared as `:binary_id` or `Ecto.UUID`. It
recognizes source aliases, primary-key overrides, `belongs_to` types and native
Ecto defaults. String business codes and external service IDs remain strings.
The check does not expand custom schema wrappers or field macros.

Use the compiled audit to cover fields and defaults supplied by those macros:

```elixir
:ok = Bylaw.Credo.StructTypes.validate(modules, sources,
  uuid_fields: true,
  uuid_primary_keys: true,
  uuid_version: 7
)
```

Each option is independent and disabled by default. `uuid_fields` checks all
actual UUID fields, including virtual fields and embedded schemas, against the
source `t/0`. `uuid_primary_keys` requires a nonempty key made entirely of UUID
fields on persisted schemas, including shared and composite keys. Embedded
schemas remain subject to field typing but are outside identity conventions.
`uuid_version` accepts 4 or 7 and
checks compiled autogeneration metadata: generated UUID keys must use native
`Ecto.UUID` generation with that version. Nongenerated shared keys pass. Adapter
generation and custom generator functions fail because their version cannot be
proved. Database-side generation is outside the compiled audit's scope.

Use the existing `TypeBeforeSchema` check to keep type declarations before
`schema` and `embedded_schema`. `FullySpecifiedStructTypes` remains a separate,
global source check; it is not restricted to Ecto schemas. For actual Postgres
column types, `Bylaw.Db.Adapters.Postgres.Checks.PrimaryKeyType` in
`bylaw_postgres` already supports `rules: [types: ["uuid"]]` and checks every
column of composite keys as well as missing keys.

The audit compares explicit source fields with actual compiled struct fields,
including fields added by schema macros and exceptions. Empty and partial
types fail; so do missing public `t/0` declarations. It returns
`{:error, issues}` with module, source location and missing fields. Supply the
whole application module list and all owned source files to cover existing
and future structs. Sources are parsed without evaluation. Type aliases and
macro-generated type declarations that cannot be attributed to an explicit
source `t/0` fail with a diagnostic.

[`NoRaise`](https://hexdocs.pm/bylaw_credo/Bylaw.Credo.Check.Elixir.NoRaise.html) and
[`NoTryRescue`](https://hexdocs.pm/bylaw_credo/Bylaw.Credo.Check.Elixir.NoTryRescue.html)
encourage explicit success/error results that can be declared as return unions
for coverage.

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
