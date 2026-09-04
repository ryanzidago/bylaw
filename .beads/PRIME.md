# Beads Workflow Context

- Use Beads for durable task tracking and create every issue with a descriptive `bylaw-<kebab-case-slug>` ID.
- Before changing tracked files, create or use a dedicated Worktrunk worktree.
- Keep the primary checkout read-only. Commits, merges, pushes, and Beads remote sync require explicit user authorization.
- Claim work with `bd update <id> --claim` and close an issue only after its work is complete.
