defmodule Bylaw.Test.SandboxUsage.Violation do
  @moduledoc """
  A passing ExUnit test that checked out a database sandbox without running any real SQL query.
  """

  @enforce_keys [:module, :test, :file, :line]
  defstruct [:module, :test, :file, :line]

  @type t :: %__MODULE__{
          module: module(),
          test: atom(),
          file: String.t() | nil,
          line: pos_integer() | nil
        }
end
