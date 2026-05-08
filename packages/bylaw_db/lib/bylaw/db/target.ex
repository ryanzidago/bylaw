defmodule Bylaw.Db.Target do
  @moduledoc """
  Target validated by database checks.

  A target represents one adapter/database query source. Adapter packages build
  targets from their own options, and checks receive targets from `Bylaw.Db`.
  """

  @typedoc """
  Optional query function for custom target wiring.
  """
  @type query_fun ::
          (__MODULE__.t(), sql :: String.t(), params :: list(term()), opts :: keyword() ->
             {:ok, term()} | {:error, term()})

  @typedoc """
  A database validation target.

  `adapter` is the adapter module that owns query execution. `repo`,
  `dynamic_repo`, `query`, and `meta` are adapter-defined fields used by adapter
  packages and custom checks.
  """
  @type t :: %__MODULE__{
          adapter: module(),
          repo: module() | nil,
          dynamic_repo: atom() | pid() | nil,
          query: query_fun() | nil,
          meta: map()
        }

  defstruct adapter: nil,
            repo: nil,
            dynamic_repo: nil,
            query: nil,
            meta: %{}
end
