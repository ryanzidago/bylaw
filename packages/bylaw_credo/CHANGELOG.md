# Changelog

## Unreleased

- Add `Bylaw.Credo.Check.Elixir.PreferBlockIf` to require block syntax for
  local and qualified Kernel `if` expressions.

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
