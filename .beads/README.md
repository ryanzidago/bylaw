# Beads issue tracking

Bylaw uses [Beads](https://github.com/gastownhall/beads) for durable, repository-local issue tracking.

## Setup

Install the pinned toolchain, initialize the local Dolt database, and verify it:

```bash
mise trust
mise install
bd init --init-if-missing --non-interactive --prefix bylaw
bd info
bd hooks list
bd setup codex --check
```

`BEADS_DIR` is resolved from Git's common directory, so the primary checkout
and every linked worktree share one local issue database.

## Human-readable issue IDs

Every issue must have a concise, descriptive ID in the
`bylaw-<kebab-case-slug>` form. Always pass the ID explicitly:

```bash
bd create --id bylaw-add-user-authentication --title="Add user authentication"
```

If an issue is accidentally created with an opaque generated ID, rename it
immediately:

```bash
bd rename bylaw-a3f2dd bylaw-descriptive-slug
```

## Everyday workflow

```bash
bd ready
bd show <issue-id>
bd update <issue-id> --claim
bd close <issue-id>
```

Run `bd prime` for the complete workflow context. Dolt remote synchronization
is separate from ordinary Git branches and requires explicit authorization:

```bash
bd dolt pull
bd dolt push
```
