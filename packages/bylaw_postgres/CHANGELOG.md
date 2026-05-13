# Changelog

## Unreleased

- Standardize every built-in Postgres check on the universal `rules:` DSL, with
  shared `where:` / `except:` scope keys and check-specific payload keys.
- Document the rule payload catalog for scope-only checks and configurable
  checks.
- Replace `only` with `where` in Postgres rule matchers.
- Require plural matcher keys and non-empty list matcher values in Postgres rules.
- Make `rules:` the only public configuration entry point for configurable
  Postgres checks.
- Remove older top-level Postgres check configuration entry points such as
  `columns:`, `scope_columns:`, `on_delete:`, `on_update:`, and top-level
  `schemas:` / `tables:` scoping on configurable checks.

## 0.1.0 - 2026-05-11

Initial package release.

- Add the `Bylaw.Db.Adapters.Postgres` validation adapter.
- Add built-in Postgres checks for foreign keys, indexes, required columns,
  primary-key types, forbidden column types, and Ecto changeset constraints.
- Add HexDocs guides for Postgres check setup, configuration, and ExUnit
  integration.
