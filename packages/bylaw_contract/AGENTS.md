# AGENTS.md

## Scope

- Keep APIs and fixes generic, using explicit modules/options and
  application-neutral reproductions.
- Umbrellas, application management, and repository/test orchestration are
  caller concerns.
- Exclude QA repos with incompatible Elixir/OTP versions; record why. No
  upgrades, backports, or shims are required. Keep failures and incomplete
  observations from compatible runs visible.

## Reporting UX

- Default output shows only actionable misses; retain other data programmatically.
- Never classify an unassessable target as missed.
- Each finding includes its location, category, source, and exact missed target.
- Typespec findings point to `@spec`; structural findings point to the exact clause.
- Report what is missing without suggesting test inputs.
