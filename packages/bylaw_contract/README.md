# Bylaw.Contract

Bylaw.Contract measures which deterministic **input classes**, exact range
boundaries, and declared **return alternatives** derived from Elixir specs were
observed by a test suite, along with gaps in **structural function clause
coverage**. It complements line coverage; it does not prove that the complete
value space of a type has been tested.

Given this spec:

```elixir
@type audience :: :admin | :member | {:guest, non_neg_integer()}
@spec greeting(audience()) :: String.t()
```

Bylaw.Contract traces test-time calls and reports whether each of `:admin`,
`:member`, and `{:guest, non_neg_integer()}` was observed. It also observes
members of top-level union return types. Explicit union members are one kind of
input class.

## Installation

Add `bylaw_contract` as a test dependency:

```elixir
def deps do
  [
    {:bylaw_contract, "~> 0.1.0", only: :test}
  ]
end
```

The package requires Erlang/OTP 27 or newer because it uses isolated sessions
from the recent `:trace` API. The Bylaw development toolchain currently tests
it on Erlang/OTP 29 with Elixir 1.20.

Checks initialize sequentially in their own workers, with earlier claims
passed to later checks. Trace sessions activate after initialization succeeds.
Check state stays in its worker; standard report fields and the per-check
coverage map are assembled in the caller when observation stops. These reduce
copying, but returned coverage and trace-event traffic still consume memory.
The compiler check cannot hot-reload the observer's own runtime modules; those
alternatives remain unassessable with a programmatic warning.

## Development

```sh
mix test
```

The default report shows only actionable gaps. If a test skips `:member`, the
report points back to the spec that declared it:

```text
Bylaw.Contract typespec gaps

MyApp.Greetings.greeting/1
    ✗ lib/my_app/greetings.ex:8
      Missed input alternative - no test exercises this declared input alternative:

      @spec greeting(audience()) :: String.t()

      argument 1: :member
```

Successful and unassessable targets remain available in the returned coverage
data and `Bylaw.Contract.summary/1`; they do not add noise to the default human
report. Loader warnings remain in `coverage.warnings`, and aggregate counters
remain available through `Bylaw.Contract.summary/1` and the summary formatter
mode; neither is printed by the default human report.

Sections without actionable gaps are omitted. When no typespec or structural
gaps exist, Bylaw.Contract prints nothing.

For a return union such as:

```elixir
@spec register(non_neg_integer()) :: {:ok, User.t()} | {:error, :underage}
```

return alternatives are reported independently from arguments. If tests return
only `{:error, :underage}`, the report includes:

```text
MyApp.Accounts.register/1
    ✗ lib/my_app/accounts.ex:14
      Missed return alternative - no test exercises this declared return alternative:

      @spec register(non_neg_integer()) ::
              {:ok, User.t()} | {:error, :underage}

      return: {:ok, User.t()}
```

Finite integer ranges also produce exact boundary targets. Given
`@spec register(0..17 | 18..120) :: term()`, calls with `17` and `18` cover both
range classes but leave two boundary gaps:

```text
MyApp.Accounts.register/1
    ✗ lib/my_app/accounts.ex:14
      Missed boundary - no test exercises this declared boundary value:

      @spec register(0..17 | 18..120) :: term()

      argument 1 boundary: 0

    ✗ lib/my_app/accounts.ex:14
      Missed boundary - no test exercises this declared boundary value:

      @spec register(0..17 | 18..120) :: term()

      argument 1 boundary: 120
```

Input classes and exact boundary values are independent signals. Observing both
range alternatives does not imply that every endpoint—or every value in either
range—was tested.

## Add it to a test suite

Add the formatter to `test_helper.exs` and select the checks to run explicitly:

```elixir
alias Bylaw.Contract.Check

ExUnit.start(
  formatters: [ExUnit.CLIFormatter, Bylaw.Contract.ExUnitFormatter],
  bylaw_contract: [
    checks: [Check.Typespec, Check.FunctionClauses]
  ]
)
```

The default check list is also `[Check.Typespec, Check.FunctionClauses]`. Pass
an explicit list to enable or disable checks independently; `checks: []`
disables all contract observation. A check spec is a check module or
`{check_module, options}`. Checks initialize in list order, and earlier checks
take precedence over later checks for overlapping obligation families.
Duplicate check modules are rejected.

For a local source trial, add Bylaw.Contract as a test-only path dependency so
the target project's own Elixir/OTP toolchain compiles it:

```elixir
{:bylaw_contract,
 path: "/absolute/path/to/bylaw/packages/bylaw_contract",
 only: :test}
```

The formatter inspects the current Mix application. For umbrella or
multi-application tests, set `BYLAW_CONTRACT_APPS=app_one,app_two`.

## Compiler-inferred return alternatives (experimental)

Elixir 1.20 records inferred public-function signatures in a private `ExCk`
BEAM chunk. Enable the Elixir compiler check after the typespec check to use
unambiguous, finite return alternatives as secondary test obligations:

```elixir
alias Bylaw.Contract.Check

ExUnit.start(
  formatters: [ExUnit.CLIFormatter, Bylaw.Contract.ExUnitFormatter],
  bylaw_contract: [
    checks: [Check.Typespec, Check.FunctionClauses, Check.ElixirCompiler]
  ]
)
```

This integration is deliberately opt-in and versioned. It reads the compiled
module already loaded by the test VM; it does not invoke or replay the
compiler. The current adapter accepts only checker version
`:elixir_checker_v8`, as emitted by the tested Elixir 1.20 toolchains. Missing
chunks, absent inference, incompatible checker versions, and descriptor shapes
that cannot be matched safely remain explicit unassessable data rather than
false gaps. Checker chunks that would require creating atoms during decoding
are rejected as unsupported. Each module is decoded in a short-lived monitored
process with a fixed time limit, so compiler descriptors whose quoted form
expands pathologically become unassessable without growing the long-lived
observer process.

Runtime obligations are limited to user-authored `def` and `defp`
definitions identified by Elixir debug metadata. Macro-generated exports are
excluded by their compiler context rather than library-specific function
names, and protocol implementation modules are excluded as a class. Generated
default-argument wrappers are also excluded because they delegate to the
authored full-arity function.
When Elixir debug information is absent, the inferred alternatives remain
available as unassessable data but Bylaw does not guess which functions were
authored or instrument them.

Check order defines precedence for overlapping obligation families. Declared
typespec obligations remain authoritative when `Check.Typespec` precedes
`Check.ElixirCompiler`.

The compiler check does not enable VM tracing and never inspects returns. It
temporarily reloads selected modules with one lightweight ETS counter injected
at each selected clause entry. A called clause credits a return alternative
only when every relevant input descriptor is supported and that compiler rule
identifies exactly one finite alternative. For example, separate `:accept` and
`:reject` function clauses can establish distinct outcomes. A single clause
whose inferred return is
`:ok | {:error, reason}` cannot establish which value was returned, so both
alternatives remain unassessable rather than becoming false gaps. This signal
demonstrates that a suite executed a clause whose compiler-inferred outcome is
unique; it does not prove a business-correct assertion.

The counters include local calls, child processes, and application background
work. This is a suite-level execution signal; it does not attribute a call to a
particular test or assertion. Original module binaries are restored when
observation stops, and Bylaw does not start the OTP `:cover` server. A module
whose abstract code cannot be recompiled remains unassessable. By default at
most 10 inferred functions are instrumented. Functions beyond that
deterministic cap are unassessable. `compiler_call_events` counts the matching
clause calls recorded by the injected counters.
Override the function cap when needed:

```elixir
checks: [
  {Check.ElixirCompiler, max_functions: 1_000}
]
```

Repeated nested aliases use a compact internal graph, including across process
handoffs. Expansion stops once a required type member is unassessable, retaining
its unsupported reason and any applicable input partitions. Each nested type
expansion allows at most 4,096 uncached alias resolutions; each top-level union
flattening allows at most 4,096 visits. Exceeding either bound makes the affected
type unassessable, never missed. These are expansion-work bounds, not a bound on
whole-suite memory or on the size of caller values. Function types are matched
by arity without expanding their unused argument and return signatures.

The current implementation resolves local and remote type aliases and handles
literals, common scalar types, tuples, lists, ranges, functions, and maps with
literal required keys. It derives deterministic classes for `integer()`
(negative, zero, positive), ranges (minimum, interior, maximum), lists (empty,
singleton, multiple), binaries (empty, non-empty), booleans, nil unions, and
explicit unions. Short ranges omit nonexistent interior classes. Exact finite
range endpoints are reported separately.

Types without a standard subdivision remain one declared-type class when their
shape can be matched safely. Recursive aliases, opaque representations, and
unsupported spec forms remain marked as unassessable in the coverage data
rather than becoming false misses; they are omitted from the default human
report. Thresholds that exist only in guards are not inferred. Top-level return
unions are observed as a separate signal. Bounded specs (`when`) are supported
when their constraints can be substituted into both argument and return types.

Union members may overlap. A value that matches more than one member (for
example, `integer() | number()`) records a hit for every matching member.

## Structural clause coverage

For compiled modules with Elixir debug information, Bylaw.Contract also reports
every user-authored `def` and `defp` clause. For each observed call it records
four separate facts:

- whether each clause head matched;
- whether each complete guard passed or rejected;
- which clause was selected after normal ordering and overlap rules;
- which authored or default-wrapper arity was called.

The default report lists only clauses that no observed test-time call selected.
It names each source-like clause head and its file/line location, so there is no
positional `clause 1`/`clause 2` lookup and successful clauses add no noise:

```text
Bylaw.Contract structural clause gaps

MyApp.Accounts.classify/1
    ✗ lib/my_app/accounts.ex:18
      Missed function clause - no test exercises this clause:

      def classify(
            %{account: %{status: status}},
            options
          )
          when status in [:active, :trial] and is_list(options)
```

The coverage result retains the raw head, guard, selection, callable-arity, and
call counts for programmatic analysis; they are intentionally omitted from the
default human report.

The classifiers are compiled from the module's BEAM abstract clauses with the
original bodies replaced by markers. They therefore preserve compiled pattern,
guard, and ordering semantics without running an original body during
classification. Compiler-generated default wrappers are retained under callable
arities but do not count as authored clauses. A module whose debug information
or abstract code is absent or unusable is retained as unsupported in the
coverage data and aggregate summary, not reported as a set of missed clauses.
Unobserved callable arities and unsupported structural modules do not appear in
the default human report.

The tracer uses isolated Erlang trace sessions and `return_trace` match
specifications, and therefore requires a recent OTP release with the `:trace`
module (OTP 27 or newer). Return tracing can affect tail-call behavior while a
session is active, so Bylaw.Contract enables it only for functions declaring a
top-level return union and destroys the session when observation stops.
