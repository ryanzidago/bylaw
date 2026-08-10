# Changelog

## Unreleased

- Narrow `Bylaw.Credo.Check.Elixir.SafeDateTimeComparison` to comparisons
  involving explicit date/time sigils and remove the `:datetime_suffixes`
  option to avoid false positives from name-based type inference.

## 0.4.0 - 2026-08-06

- Add `Bylaw.Credo.Plugin.DisableForNextDefinition` for AST-ranged suppression
  of named or all Credo checks within the next `def` or `defp` clause. Require
  Credo 1.7.16 or newer for exact definition-range token metadata and supported
  Elixir compiler compatibility.

## 0.3.1 - 2026-08-06

- Add `Bylaw.Credo.Check.Ecto.PreferOrderByOverRepoAllEnumSort` to discourage
  sorting `Repo.all` results in memory instead of using `order_by`.

## 0.3.0 - 2026-08-06

- Update `Bylaw.Credo.Check.Elixir.SafeDateTimeComparison` to ignore direct
  date/time comparisons anywhere inside Ecto query expressions.
- Add `Bylaw.Credo.Check.HEEx.DesignSystem.NoArbitrarySpacing` to discourage
  raw pixel spacing values in static HEEx and HTML class and style attributes.
- Add `Bylaw.Credo.Check.HEEx.NoIndirectAssignAccess` to discourage indirect
  access to the special HEEx `assigns` variable.
- Add `Bylaw.Credo.Check.Elixir.NoRemoteCallsInModuleAttributes` to avoid
  application and dependency calls that create compile-time dependencies from
  module attributes while allowing literals and standard-library calls.
- Add `Bylaw.Credo.Check.PhoenixLiveView.RequireFunctionComponentAttrs` to
  require explicit `attr` and `slot` contracts for HEEx function components
  while excluding LiveView `render/1` page assigns.
- Add `Bylaw.Credo.Check.Ecto.PreferRepoOneOverAllFirst` to report queries
  that load every matching row with `Repo.all` before taking the first result
  with `List.first`, `Enum.at(0)`, or `hd`.
- Add `Bylaw.Credo.Check.Ecto.NoDataChangesInSchemaMigrations` to keep Ecto
  schema migrations focused on DDL and direct row mutations in reviewed,
  resumable data-migration scripts or release tasks.
- Add `Bylaw.Credo.Check.Testing.PreferSelectorAssertionsForHtml` to discourage
  brittle test comparisons against serialized HTML attribute order.
- Update `Bylaw.Credo.Check.Testing.NoGlobalStateInTests` to recommend stable
  environment-specific configuration.
- Add `Bylaw.Credo.Check.Elixir.PreferBlockIf` to require block syntax for
  local and qualified Kernel `if` expressions.
- Add `Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues` to require complex
  tagged-tuple values to be bound to variables.
- Add `Bylaw.Credo.Check.Testing.NoDescribeBlocks` to require descriptive
  standalone tests and focused test files instead of `describe` blocks.

## 0.2.0 - 2026-07-27

- Add `Bylaw.Credo.Check.Ecto.ContextOwnsSchemaQueries` to enforce configured
  Phoenix context ownership for Ecto schema query and Repo CRUD logic.
- Support HEEx checks with the tokenizer module used by Phoenix LiveView 1.2.

## 0.1.1 - 2026-05-13

- Add the `Bylaw.Credo.Check.HEEx.PreferLinkForNavigation` check for HEEx
  `phx-click` navigation handlers on non-link tags and components.

## 0.1.0 - 2026-05-11

Initial package release.

- Add custom Credo checks under `Bylaw.Credo.Check`.
- Add checks for common Elixir, Ecto, Phoenix, test, and project-style
  constraints.
