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
- When doing code review for a PR, use the PR's linked worktree when one exists and applies.
- Treat every worktree as owned by the session that created or was assigned to
  it. Do not remove, reset, or repurpose another session's worktree. If
  ownership or activity is uncertain, leave it in place and report it.
- The post-merge hook removes clean worktrees for merged PRs and clean
  worktrees for closed PRs. It preserves dirty worktrees, open or reopened PRs,
  branches without PRs, and the local branch for a closed-but-unmerged PR.
- Keep unrelated changes out of the same commit or PR.
- Read the nearby code and tests before changing behavior.
- Prefer focused, explicit modules over broad orchestration APIs.
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

This repository keeps commit-ready Git hooks in `.githooks/` for `pre-commit`, `pre-push`, `post-merge`, and rebase `post-rewrite` checks. Enable them once per worktree:

```sh
git config core.hooksPath .githooks
```

The `.githooks/` scripts are tracked executable files, so they are present in
new worktrees automatically. Worktrunk runs `git config core.hooksPath
.githooks` for new worktrees.

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
