defmodule Bylaw do
  @moduledoc """
  Validation helpers for code, database, and schema constraints.

  Bylaw is organized around check families:

  - `Bylaw.Ecto.Query` validates prepared Ecto query structs before repo
    operations run.
  - `Bylaw.Db` validates database structure through adapter-specific targets.
  - `Bylaw.Credo` is planned for custom Credo checks.
  """
end
