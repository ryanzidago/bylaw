# Changelog

## Unreleased

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
