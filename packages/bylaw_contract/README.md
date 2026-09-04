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

Start the tracer after `ExUnit.start/0`, naming the application modules to
inspect, and print the result after the suite:

```elixir
ExUnit.start()

{:ok, tracer} = Bylaw.Contract.start([MyApp.Accounts, MyApp.Billing])

ExUnit.after_suite(fn _result ->
  tracer
  |> Bylaw.Contract.stop()
  |> Bylaw.Contract.print_report()
end)
```

For a no-code-change trial, put Bylaw.Contract's compiled `ebin` directory on the
code path and add its formatter alongside ExUnit's normal formatter:

```sh
BYLAW_CONTRACT_REPORT=summary \
  elixir -pa /path/to/bylaw_contract/_build/test/lib/bylaw_contract/ebin \
  -e ':application.load(:bylaw_contract); Enum.each(Application.spec(:bylaw_contract, :modules), &Code.ensure_loaded!/1)' \
  -S mix test \
  --formatter ExUnit.CLIFormatter \
  --formatter Bylaw.Contract.ExUnitFormatter
```

The formatter inspects the current Mix application. For umbrella or
multi-application tests, set `BYLAW_CONTRACT_APPS=app_one,app_two`. The eager-load
step is needed for a path-only trial because Mix removes code paths that are
not project dependencies; it is unnecessary once Bylaw.Contract is a dependency.

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
