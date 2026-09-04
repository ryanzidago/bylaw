# AGENTS.md

## Reporting UX

- Default output shows only actionable misses; retain other data programmatically.
- Never classify an unassessable target as missed.
- Each finding includes its location, category, source, and exact missed target.
- Typespec findings point to `@spec`; structural findings point to the exact clause.
- Report what is missing without suggesting test inputs.
