defmodule Bylaw.HTML.Issue do
  @moduledoc """
  Issue returned by rendered HTML validation.
  """

  @type t :: %__MODULE__{
          check: module(),
          message: String.t(),
          tag: String.t() | nil,
          snippet: String.t() | nil
        }

  defstruct check: nil,
            message: "",
            tag: nil,
            snippet: nil
end
