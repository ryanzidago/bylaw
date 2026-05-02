defmodule Bylaw.Ecto.Query.Issue do
  @moduledoc """
  Describes a query validation issue found by a check.
  """

  @type t :: %__MODULE__{
          check: module(),
          message: String.t(),
          meta: map()
        }

  defstruct check: nil,
            message: "",
            meta: %{}
end
