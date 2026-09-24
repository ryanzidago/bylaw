defmodule Bylaw.Ecto.Query.RuleOptionsUnloadedSchemaTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.MandatoryWhereKeys

  @moduletag :tmp_dir

  test "an ecto_schemas matcher accepts a schema module that is not loaded yet", %{
    tmp_dir: tmp_dir
  } do
    schema = unloaded_schema!(tmp_dir)
    query = from(post in "posts", as: :post)

    assert :ok =
             MandatoryWhereKeys.validate(:all, query,
               rules: [where: [ecto_schemas: [schema]], fields: [:organization_id]]
             )
  end

  # Compiles a schema to a .beam on the code path, then unloads it, like a module
  # that nothing has used yet in an interactive-mode test run.
  defp unloaded_schema!(tmp_dir) do
    schema = Module.concat(__MODULE__, "Unloaded#{System.unique_integer([:positive])}")

    [{^schema, binary}] =
      Code.compile_string("""
      defmodule #{inspect(schema)} do
        use Ecto.Schema

        schema "unloaded_posts" do
          field(:organization_id, :integer)
        end
      end
      """)

    File.write!(Path.join(tmp_dir, "#{schema}.beam"), binary)
    Code.prepend_path(tmp_dir)
    :code.purge(schema)
    :code.delete(schema)
    refute :code.is_loaded(schema)

    schema
  end
end
