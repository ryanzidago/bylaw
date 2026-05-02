defmodule Bylaw.Db.Target do
  @moduledoc """
  A single database validation target.

  A target intentionally represents one adapter/database/schema combination.
  Multi-database and multi-schema validation is modeled as a list of explicit
  targets.
  """

  @typedoc """
  Query callback useful for tests and custom source wiring.
  """
  @type query_fun ::
          (__MODULE__.t(), sql :: String.t(), params :: list(term()), opts :: keyword() ->
             {:ok, term()} | {:error, term()})

  @type t :: %__MODULE__{
          adapter: module(),
          name: atom(),
          repo: module() | nil,
          dynamic_repo: atom() | pid() | nil,
          schema: String.t(),
          query: query_fun() | nil,
          meta: map()
        }

  defstruct adapter: nil,
            name: nil,
            repo: nil,
            dynamic_repo: nil,
            schema: nil,
            query: nil,
            meta: %{}
end
