defmodule Bylaw.Db.Target do
  @moduledoc """
  A single database validation target.

  A target intentionally represents one adapter/database query source. Checks
  own any schema, table, or other scope filtering they support.
  """

  @typedoc """
  Query callback useful for tests and custom source wiring.
  """
  @type query_fun ::
          (__MODULE__.t(), sql :: String.t(), params :: list(term()), opts :: keyword() ->
             {:ok, term()} | {:error, term()})

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
