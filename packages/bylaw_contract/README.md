# Bylaw.Contract

Line coverage tells you which functions ran. **Bylaw.Contract tells you which
properties of a function no test exercised.**

A property is a fact declared in your code:

| Property | Declared in | Reported when |
|---|---|---|
| **Head** | function clauses | no test selected the clause |
| **Guard** | `when` | no test made the guard reject a call that a later clause handled |
| **Type** | `@spec` | no test passed an argument alternative or a range boundary, or produced a return alternative |

```elixir
defmodule MyApp.Accounts do
  @type audience :: :admin | :member | {:guest, non_neg_integer()}

  @spec greet(audience()) :: String.t()
  def greet(:admin), do: "admin"
  def greet(:member), do: "member"
  def greet({:guest, _id}), do: "guest"
end
```

If the suite only greets admins and members, the report says so:

```text
Bylaw.Contract gaps

MyApp.Accounts.greet/1
    ✗ lib/my_app/accounts.ex:7
      Untested clause - no test selected clause 3:

      def greet({:guest, _id}), do: "guest"

      clause 3

    ✗ lib/my_app/accounts.ex:5
      Untested argument alternative - no test passed this declared alternative:

      @spec greet(audience()) :: String.t()

      argument 1: {:guest, non_neg_integer()}
```

It prints nothing when no property is missed, and it never reports something it
cannot assess (opaque types, recursive return values) as missed.

## Installation

```elixir
def deps do
  [{:bylaw_contract, "~> 0.1.0", only: :test}]
end
```

Requires Elixir 1.19 or newer.

## Use it in a test suite

```elixir
# test/test_helper.exs
ExUnit.start(formatters: [ExUnit.CLIFormatter, Bylaw.Contract.ExUnitFormatter])
```

The formatter observes the modules of the current Mix application and prints
the report when the suite ends. It never changes the suite's result. Observe
other modules with `bylaw_contract: [modules: [MyApp.Accounts]]`.

Or observe any code directly:

```elixir
report = Bylaw.Contract.observe([MyApp.Accounts], fn -> run_checks() end)
Bylaw.Contract.Report.print(report)
```

`report.properties` holds every property with its `status` (`:observed`,
`:missed`, `:unassessable`) and `count`; `report.warnings` explains modules or
functions that could not be observed.

## Review only what a pull request changed

On a large suite the full report is long. Pass a git revision to report only the
functions whose clauses or `@spec`s changed since it, plus every function in files
git does not track yet:

```elixir
ExUnit.start(
  formatters: [ExUnit.CLIFormatter, Bylaw.Contract.ExUnitFormatter],
  bylaw_contract: [since: "origin/main"]
)
```

or set `BYLAW_CONTRACT_SINCE=origin/main` in CI. An unknown revision raises, so a
typo cannot silently report nothing. Observation still covers the whole suite;
only the printout is narrowed.

## Dismiss findings once

Some findings need a human to dismiss: a defensive clause, a `@spec` wider than the
code, an input validated upstream. Record the current findings in a file and commit
it; later runs print only findings that are not in it:

```elixir
ExUnit.start(
  formatters: [ExUnit.CLIFormatter, Bylaw.Contract.ExUnitFormatter],
  bylaw_contract: [baseline: "test/bylaw_contract_baseline.txt"]
)
```

```text
BYLAW_CONTRACT_UPDATE_BASELINE=1 mix test   # rewrite the file from this run
```

Entries are keyed by function, kind, clause, argument and label, never by line
number, so edits above a finding do not bring it back. Delete a line to see that
finding again. Rewrite the baseline from a full, passing run: excluded or failing
tests add findings that the next run would otherwise hide. The formatter prints how
many findings the baseline hid. `since:` and `baseline:` combine.

## How it works

Observation reloads each module with a small prologue in every clause. Selecting
a clause, rejecting a call in a guard, or passing a value of a declared type bumps
a counter in the calling process. There is no tracing, no extra process, and no
queue, so nothing can fall behind or be dropped, and the original modules are
restored when observation stops.

## Reading the report

A finding is a fact about the run that was observed, not about every test in the
repository:

- Tests excluded by tag, skipped, or failing do not count. The formatter prints
  how many there were; a finding that a tagged-out test would cover disappears
  when that test runs.
- Code that runs before observation starts, such as a supervisor's `init/1`
  during application boot, is not seen.
- A gap means one of three things, and all three are worth acting on: a test is
  missing, the `@spec` or guard is wider than the code (narrow it so it says what
  the code does), or the clause is dead (delete it). The tool cannot tell which, so
  the report asks you to decide.
- A guard property exists only when a later clause's patterns could match a call
  the guard rejects. A guard that validation upstream keeps from ever rejecting is
  still reported: either test it or drop the guard.
- Only declared alternatives are reported: union members, `boolean()`, and the
  endpoints of an integer range. A plain `String.t()` or `list()` has one
  alternative and no property.

## Limits

- Only public functions get clause and guard properties. Functions with a single
  clause have no clause property, and the last clause has no guard property
  because a rejected call raises before anything can record it.
- A call that matches no clause raises before it can be recorded.
- Return values of recursive functions are not observed, because that would
  remove tail-call optimisation; their return alternatives are `:unassessable`.
- Lists are checked against their types up to 32 cells per call, so a malformed
  list beyond that prefix can match.
- Modules need debug information and a BEAM file. Others produce a warning.
- One observation can be active at a time.
- A module that processes are still executing cannot be reloaded or restored;
  it is skipped with a warning and never forcibly purged.
