# AGENTS.md

Guidance for humans and LLM agents working in Bylaw.

## Project

Bylaw is an Elixir library for validating code, database, query, schema, and workflow constraints. Keep public APIs small until repeated usage proves a larger abstraction is needed.

Bylaw should stay as zero-config as practical. Prefer explicit arguments and data passed by callers over reading from application config. Callers may load configuration however they like, but Bylaw should not expect checks, rules, or validation inputs to be registered in application config.

Keep APIs minimal and direct. Add only the surface area needed to get the job done, and avoid complex orchestration unless repeated usage shows the need.

## Workflow

- Use Worktrunk (`wt`) as the primary interface for worktree lifecycle and
  management.
- Never modify files, stage changes, commit, or push while the current branch
  is `main` or `master`.
- Before changing the repository, create a dedicated linked worktree under
  `.worktrees/`, or reuse the existing worktree for the branch or PR being
  continued.
- Use a separate linked worktree and branch for each independent task.
- Create and switch task worktrees with `wt switch --create <branch>` or
  `wt switch <branch>`.
- Review PRs with `wt switch pr:<number>` when possible.
- If worktree creation fails, inspect `wt list` and the branch state for a
  partially-created worktree, then attempt safe recovery. If no dedicated
  worktree can be used, stop and report the blocker instead of changing the
  primary checkout.
- List worktrees with `wt list`; remove only the current session's completed
  worktree with `wt remove`.
- Use `wt step diff` to review the full task diff from the branch point.
- Create an explicitly stacked worktree from the current branch with
  `wt stack <branch>`.
- The `pre-switch` hook refreshes the primary worktree from its upstream with a
  fast-forward-only update. Investigate failures instead of bypassing the hook
  or changing the primary checkout.
- Do not use raw `git worktree` commands for routine task work unless `wt`
  cannot handle the case.
- Do not close, reopen, merge, or delete GitHub PRs or remote branches unless
  the user explicitly asks for that GitHub-side state change.
- When creating a GitHub PR from an issue, include a closing keyword such as
  `Closes #123` in the PR description when merging the PR will fully satisfy
  the issue, so GitHub automatically closes the issue when the PR is merged.
- When doing code review for a PR, use the PR's linked worktree when one exists and applies.
- Treat every worktree as owned by the session that created or was assigned to
  it. Do not remove, reset, or repurpose another session's worktree. If
  ownership or activity is uncertain, leave it in place and report it.
- The post-merge hook removes clean worktrees for merged PRs and clean
  worktrees for closed PRs. It preserves dirty worktrees, open or reopened PRs,
  branches without PRs, and the local branch for a closed-but-unmerged PR.
- Finished-PR cleanup is deferred when a post-merge hook runs inside the
  Worktrunk pre-switch refresh, preserving the active switch's source worktree.
  A later ordinary post-merge cleanup can remove those completed worktrees.
- Keep unrelated changes out of the same commit or PR.
- Read the nearby code and tests before changing behavior.
- Prefer focused, explicit modules over broad orchestration APIs.
- Write created artifacts, including pull requests, GitHub issues, plans, and
  handoff notes, for a zero-context reader. Each artifact should stand on its
  own so another human or LLM can act on it without access to prior
  conversations. Include the problem, why it matters, the relevant context and
  constraints, the intended outcome, and enough scope, acceptance criteria,
  decisions, references, and verification details to continue the work
  confidently.
- Use acceptance-test-driven development for behavior changes:
  1. Inventory the acceptance criteria as named, empty acceptance tests at the
     appropriate boundary. Do not mark them as TODO, skip them, tag them to be
     excluded, or otherwise prevent them from running. Even while empty, they
     must run with the normal test suite and document the agreed test plan.
  2. After the acceptance inventory is agreed, implement the test bodies and
     run them against the unchanged behavior to prove they fail.
  3. Implement the smallest change that makes the tests pass.
  4. Refactor while keeping the tests green.

  Use `test "name" do end` for an empty acceptance test.

  Do not use `describe` blocks to organize tests. Keep test names descriptive
  and split a growing suite into multiple focused test files, including
  multiple test files for the same module or feature when appropriate.
- Add or update tests for behavior changes and regressions.
- Consider property-based testing with StreamData when behavior expresses broad
  invariants across many inputs, such as ordering, preservation, normalization,
  round trips, equivalence, idempotence, or parser behavior.
- Prefer properties with an independent oracle or metamorphic relationship.
  Do not reproduce the implementation in the assertion.
- Keep deterministic example tests for important boundary cases and readable
  regressions. Property tests complement rather than replace acceptance and
  integration tests.
- Add StreamData only to packages containing useful properties, as a test-only
  dependency.

Configure Worktrunk once per machine so new worktrees stay inside this repo:

```sh
mise trust
mise install
wt config create
```

Set the user config value:

```toml
worktree-path = "{{ repo_path }}/.worktrees/{{ branch | sanitize }}"
```

After reviewing `.config/wt.toml`, approve its hooks and aliases once:

```sh
wt config approvals add
```

Do not use `--yes` as a routine substitute for saved approval. Reserve it for
deliberate non-interactive automation.

If user config is unavailable, pass the path template for the command:

```sh
WORKTRUNK_WORKTREE_PATH='{{ repo_path }}/.worktrees/{{ branch | sanitize }}' wt switch --create <branch>
```

Useful Worktrunk commands for agents:

```sh
wt switch --create codex/<task>
wt switch pr:<number>
wt stack codex/<stacked-task>
wt step diff
wt remove
wt step prune --dry-run
```

Treat `wt step prune --dry-run` as a diagnostic only. Do not run the pruning
action without resolving every candidate's ownership and confirming that broad
local branch cleanup is intended.

## Elixir Conventions

- Public functions need `@doc` and `@spec`.
- Prefer `list(...)` in typespecs instead of `[...]`.
- Use `@impl BehaviourModule`, not `@impl true`.
- Prefer `Enum.empty?/1` or `Enum.any?/2` over comparing collections to `[]`.
- Keep comments rare and useful; prefer clear names and small functions.

## Validation

Run `scripts/qa.sh` before committing, before pushing, and before opening or updating a PR:

```sh
scripts/qa.sh
```

This repository keeps commit-ready Git hooks in `.githooks/` for `pre-commit`, `pre-push`, `post-merge`, and rebase `post-rewrite` checks. Enable the repository hooks and their Beads integration once per worktree:

```sh
scripts/install-hooks
```

The `.githooks/` scripts are tracked executable files, so they are present in
new worktrees automatically. `scripts/install-hooks` preserves those checks and
adds Beads' hook dispatcher. Worktrunk runs it for new worktrees.

If a command cannot run, include the reason in the PR notes.

<!-- usage-rules-start -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should *thoroughly* consult before taking any
action. These usage rules contain guidelines and rules *directly from the package authors*.
They are your best source of knowledge for making decisions.

## Modules & functions in the current package and dependencies

There is no root Mix project. When looking for docs for modules & functions that
are dependencies of a package, or for Elixir itself, run documentation commands
from that package directory when the package has the relevant tooling available.

```
# Search a whole module
cd packages/bylaw_ecto_query
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```


## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best 
way to accomplish this is to use the `usage_rules.search_docs` mix task from the
relevant package when available. Once you have found what you are looking for,
use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
cd packages/bylaw_ecto_query
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```


<!-- usage_rules-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
# OTP Usage Rules

## GenServer Best Practices
- Keep state simple and serializable
- Handle all expected messages explicitly
- Use `handle_continue/2` for post-init work
- Implement proper cleanup in `terminate/2` when necessary

## Process Communication
- Use `GenServer.call/3` for synchronous requests expecting replies
- Use `GenServer.cast/2` for fire-and-forget messages.
- When in doubt, use `call` over `cast`, to ensure back-pressure
- Set appropriate timeouts for `call/3` operations

## Fault Tolerance
- Set up processes such that they can handle crashing and being restarted by supervisors
- Use `:max_restarts` and `:max_seconds` to prevent restart loops

## Task and Async
- Use `Task.Supervisor` for better fault tolerance
- Handle task failures with `Task.yield/2` or `Task.shutdown/2`
- Set appropriate task timeouts
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure

<!-- usage_rules:otp-end -->
<!-- usage-rules-end -->

## Beads task scope

- Record out-of-scope issues as deferred in Beads; check for duplicates first.
- Never promote or work on deferred or blocked issues without explicit user approval.

## Beads issue IDs

Give every new Beads issue a concise, descriptive, human-readable ID prefixed
with its owning package name, replacing underscores with hyphens. Pass the ID
explicitly to `bd create`: for example, `--id bylaw-contract-<kebab-case-slug>`
for `bylaw_contract`, or `--id bylaw-ecto-query-<kebab-case-slug>` for
`bylaw_ecto_query`. Use `bylaw-<kebab-case-slug>` for shared repository
workflow tasks that do not belong to one package.

Immediately rename any issue created with an opaque generated ID or without
the appropriate package prefix. Use `bd rename <old-id> <new-id>` to preserve
the issue and update its references and dependencies.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:970c3bf2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **Record follow-ups** - Follow the Beads task scope rules above.
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   bd dolt push
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->

<!-- BEGIN BEADS CODEX SETUP: generated by bd setup codex -->
## Beads Issue Tracker

Use Beads (`bd`) for durable task tracking in repositories that include it. Use the `beads` skill at `.agents/skills/beads/SKILL.md` (project install) or `~/.agents/skills/beads/SKILL.md` (global install) for Beads workflow guidance, then use the `bd` CLI for issue operations.

### Quick Reference

```bash
bd ready                # Find available work
bd show <id>            # View issue details
bd update <id> --claim  # Claim work
bd close <id>           # Complete work
bd prime                # Refresh Beads context
```

### Rules

- Use `bd` for all task tracking; do not create markdown TODO lists.
- Run `bd prime` when Beads context is missing or stale. Codex 0.129.0+ can load Beads context automatically through native hooks; use `/hooks` to inspect or toggle them.
- Keep persistent project memory in Beads via `bd remember`; do not create ad hoc memory files.

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.
<!-- END BEADS CODEX SETUP -->
