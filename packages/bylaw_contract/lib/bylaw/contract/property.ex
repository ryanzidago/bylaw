defmodule Bylaw.Contract.Property do
  @moduledoc """
  A testable fact about a function, declared in its source.

  Kinds:

    * `:clause` - a function clause that a call can select
    * `:guard_rejection` - a guard that can reject a call a later clause handles
    * `:argument_class` - a declared `@spec` alternative of an argument
    * `:argument_boundary` - an exact boundary of a declared integer range
    * `:return_alternative` - a declared `@spec` member of the return union

  A property is `:observed` when a test exercised it, `:missed` when none did,
  and `:unassessable` when it cannot be assessed, so it is never reported as
  missed.
  """

  @type kind ::
          :clause | :guard_rejection | :argument_class | :argument_boundary | :return_alternative

  @type status :: :observed | :missed | :unassessable

  @type t :: %__MODULE__{
          id: term(),
          kind: kind(),
          module: module(),
          function: atom(),
          arity: arity(),
          clause: pos_integer() | nil,
          argument: pos_integer() | nil,
          label: String.t() | nil,
          file: String.t() | nil,
          line: non_neg_integer() | nil,
          source: String.t() | nil,
          slot: pos_integer() | nil,
          unknown_slot: pos_integer() | nil,
          reason: String.t() | nil,
          count: non_neg_integer(),
          status: status()
        }

  defstruct [
    :id,
    :kind,
    :module,
    :function,
    :arity,
    :clause,
    :argument,
    :label,
    :file,
    :line,
    :source,
    :slot,
    :unknown_slot,
    :reason,
    count: 0,
    status: :missed
  ]
end
