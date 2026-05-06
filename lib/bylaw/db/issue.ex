defmodule Bylaw.Db.Issue do
  @moduledoc """
  Describes a database validation issue found by a check.
  """

  alias Bylaw.Db.Target

  @type t :: %__MODULE__{
          check: module(),
          message: String.t(),
          target: Target.t() | nil,
          meta: map()
        }

  defstruct check: nil,
            message: "",
            target: nil,
            meta: %{}
end
