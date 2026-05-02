# AGENTS.md

Guidance for humans and LLM agents working in Bylaw.

## Project

Bylaw is an Elixir library for validating code, database, query, schema, and workflow constraints. Keep public APIs small until repeated usage proves a larger abstraction is needed.

## Workflow

- Do all task work in a linked git worktree under `.worktrees/`.
- Use a separate linked worktree and branch for each independent task.
- Keep unrelated changes out of the same commit or PR.
- Read the nearby code and tests before changing behavior.
- Prefer focused, explicit modules over broad orchestration APIs.
- Add tests before fixing bugs when the current behavior can be reproduced.

## Elixir Conventions

- Public functions need `@doc` and `@spec`.
- Prefer `list(...)` in typespecs instead of `[...]`.
- Use `@impl BehaviourModule`, not `@impl true`.
- Prefer `Enum.empty?/1` or `Enum.any?/2` over comparing collections to `[]`.
- Keep comments rare and useful; prefer clear names and small functions.

## Validation

Before opening or updating a PR, run:

```sh
mix format
mix test
mix compile --warnings-as-errors
```

If a command cannot run, include the reason in the PR notes.

<!-- usage-rules-start -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should *thoroughly* consult before taking any
action. These usage rules contain guidelines and rules *directly from the package authors*.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```


## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best 
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
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
