# Changelog

## 0.1.0 - 2026-05-11

Initial package release.

- Add generic database validation contracts.
- Add `Bylaw.Db.Target` and `Bylaw.Db.Issue` data structures.
- Add the shared `Bylaw.Db.validate/2` check runner.
- Add `Bylaw.Db.Issue.format/1`, `format/2`, `format_many/1`, and
  `format_many/2` for human-readable database issue output.
- Omit issue metadata from formatted database issue output by default, with
  `meta: true` for verbose debugging.
