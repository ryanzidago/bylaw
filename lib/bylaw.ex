defmodule Bylaw do
  @moduledoc """
  Validation helpers for code, database, and schema constraints.

  Bylaw is organized around check families:

  - `Bylaw.Ecto.Query` validates prepared Ecto query structs before repo
    operations run.
  - `Bylaw.Credo` is planned for custom Credo checks.
  - `Bylaw.Db` is planned for checks derived from database schema constraints.
  """
end
