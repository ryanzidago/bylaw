defmodule Bylaw.Contract.Check do
  @moduledoc """
  Behaviour implemented by runtime contract checks.

  Checks declare the function calls and returns they need to observe, consume
  matching trace events, and return their coverage data when observation ends.
  """

  @typedoc "A module, function, and arity observed by a check."
  @type observed_mfa :: {module(), atom(), arity()}

  @typedoc "A runtime event delivered to enabled checks."
  @type event :: {:call, observed_mfa(), list(term())} | {:return, observed_mfa(), term()}

  @typedoc "An observation that a check no longer needs traced."
  @type completion :: {:call | :return, observed_mfa()}

  @typedoc "A check state update, optionally with completed trace interests."
  @type observe_result :: term() | {:complete, term(), list(completion())}

  @typedoc "Check-specific options supplied in a check spec."
  @type opts :: list({atom(), term()})

  @typedoc "Claims made by checks initialized earlier in the configured list."
  @type context :: %{claims: MapSet.t(term())}

  @typedoc "Trace interests and claims produced while initializing a check."
  @type plan :: %{
          optional(:process_scope) => :all | :new | :ex_unit_tests,
          optional(:trace_scope) => :global | :local,
          calls: MapSet.t(observed_mfa()),
          returns: MapSet.t(observed_mfa()),
          claims: MapSet.t(term())
        }

  @doc "Initializes a check for the modules being observed."
  @callback init(list(module()), opts(), context()) ::
              {:ok, state :: term(), plan()} | {:error, String.t()}

  @doc "Consumes one matching runtime event and may retire completed trace interests."
  @callback observe(event(), state :: term()) :: observe_result()

  @doc """
  Returns the coverage data accumulated by the check.

  The result is retained under the check module in the final `:checks` map.
  Built-in checks also return the shared fields consumed by Bylaw's standard
  report.
  """
  @callback coverage(state :: term()) :: map()

  @doc "Releases resources owned by the check."
  @callback terminate(state :: term()) :: :ok
end
