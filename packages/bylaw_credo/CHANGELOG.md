# Changelog

## Unreleased

- Add `Bylaw.Credo.Check.Ecto.ContextOwnsSchemaQueries` to enforce configured
  Phoenix context ownership for Ecto schema query and Repo CRUD logic.

## 0.1.1 - 2026-05-13

- Add the `Bylaw.Credo.Check.HEEx.PreferLinkForNavigation` check for HEEx
  `phx-click` navigation handlers on non-link tags and components.

## 0.1.0 - 2026-05-11

Initial package release.

- Add custom Credo checks under `Bylaw.Credo.Check`.
- Add checks for common Elixir, Ecto, Phoenix, test, and project-style
  constraints.
