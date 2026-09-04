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

The included test intentionally skips `:member`, so the report ends with a
miss:

```text
Bylaw.Contract.Example.greeting/2, argument 1
  Input classes: 2/3 supported observed across 2 calls
    HIT   :admin (1 call)
    MISS  :member
    HIT   {:guest, non_neg_integer()} (1 call)
```

For a return union such as:

```elixir
@spec register(non_neg_integer()) :: {:ok, User.t()} | {:error, :underage}
```

normal return values are reported independently from arguments:

```text
MyApp.Accounts.register/1, return
  Return alternatives: 2/2 supported observed across 3 returns
    HIT   {:ok, User.t()} (1 return)
    HIT   {:error, :underage} (2 returns)
```

Finite integer ranges also produce exact boundary targets. Given
`@spec register(0..17 | 18..120) :: term()`, calls with `17` and `18` produce:

```text
  Input classes: 2/2 supported observed across 2 calls
    HIT   0..17 (1 call)
    HIT   18..120 (1 call)
  Boundary values: 2/4 observed
    MISS  0
    HIT   17 (1 call)
    HIT   18 (1 call)
    MISS  120
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
unsupported spec forms remain explicit as `????` instead of being reported as
false misses. Thresholds that exist only in guards are not inferred. Top-level
return unions are observed as a separate signal. Bounded specs (`when`) are
supported when their constraints can be substituted into both argument and
return types.

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
      no test exercises this clause:

      def classify(
            %{account: %{status: status}},
            options
          )
          when status in [:active, :trial] and is_list(options)
```

The coverage result retains the raw head, guard, selection, and call counts for
programmatic analysis; they are intentionally omitted from the default human
report.

The classifiers are compiled from the module's BEAM abstract clauses with the
original bodies replaced by markers. They therefore preserve compiled pattern,
guard, and ordering semantics without running an original body during
classification. Compiler-generated default wrappers are listed under callable
arities but do not count as authored clauses. A module whose debug information
or abstract code is absent or unusable is explicitly reported as unsupported,
not as a set of missed clauses.

The tracer uses isolated Erlang trace sessions and `return_trace` match
specifications, and therefore requires a recent OTP release with the `:trace`
module (OTP 27 or newer). Return tracing can affect tail-call behavior while a
session is active, so Bylaw.Contract enables it only for functions declaring a
top-level return union and destroys the session when observation stops.
