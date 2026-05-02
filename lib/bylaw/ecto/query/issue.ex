defmodule Bylaw.Ecto.Query.Issue do
  @moduledoc """
  Describes a query validation issue found by a check.
  """

  @type t :: %__MODULE__{
          check: module(),
          code: atom(),
          message: String.t(),
          meta: map()
        }

  defstruct check: nil,
            code: nil,
            message: "",
            meta: %{}
end
