defmodule Bylaw.Credo.StructTypesUUIDTest do
  use ExUnit.Case, async: true

  alias Bylaw.Credo.StructTypes

  alias __MODULE__.AdapterGenerated
  alias __MODULE__.Composite
  alias __MODULE__.CustomGenerated
  alias __MODULE__.Embedded
  alias __MODULE__.EmbeddedForm
  alias __MODULE__.Inherited
  alias __MODULE__.Keyless
  alias __MODULE__.NativeGenerated
  alias __MODULE__.Natural
  alias __MODULE__.Shared
  alias __MODULE__.VersionFour
  alias __MODULE__.VersionSeven

  test "checks actual inherited UUID fields against explicit source types" do
    assert {:error, issues} = validate(Inherited, uuid_fields: true)
    assert Enum.map(issues, & &1.missing_fields) == [[:id, :macro_id, :owner_id, :virtual_id]]
    assert Enum.all?(issues, &(&1.reason == :uuid_field_type))
    assert :ok = validate(Shared, uuid_fields: true)
  end

  test "requires UUID primary keys only when requested" do
    assert :ok = validate(Natural, [])
    assert {:error, [issue]} = validate(Natural, uuid_primary_keys: true)
    assert issue.reason == :uuid_primary_key
    assert {:error, [issue]} = validate(Keyless, uuid_primary_keys: true)
    assert issue.reason == :uuid_primary_key
    assert :ok = validate(Shared, uuid_primary_keys: true)
    assert {:error, [issue]} = validate(Composite, uuid_primary_keys: true)
    assert issue.reason == :uuid_primary_key
  end

  test "checks native UUID generation version and permits shared primary keys" do
    assert :ok = validate(VersionSeven, uuid_primary_keys: true, uuid_version: 7)
    assert :ok = validate(NativeGenerated, uuid_version: 7)
    assert {:error, [issue]} = validate(CustomGenerated, uuid_version: 7)
    assert issue.reason == :uuid_generation
    assert :ok = validate(Shared, uuid_primary_keys: true, uuid_version: 7)
    assert {:error, [issue]} = validate(VersionFour, uuid_version: 7)
    assert issue.reason == :uuid_generation
    assert {:error, [issue]} = validate(AdapterGenerated, uuid_version: 7)
    assert issue.reason == :uuid_generation
  end

  test "checks embedded schema UUID identities and preserves external strings" do
    assert {:error, [issue]} = validate(Embedded, uuid_fields: true)
    assert issue.reason == :uuid_field_type
    assert issue.missing_fields == [:id]
  end

  test "leaves keyless embedded forms outside persisted identity conventions" do
    assert :ok =
             validate(EmbeddedForm, uuid_fields: true, uuid_primary_keys: true, uuid_version: 7)

    assert {:error, [issue]} =
             validate(Keyless, uuid_fields: true, uuid_primary_keys: true, uuid_version: 7)

    assert issue.reason == :uuid_primary_key
  end

  test "rejects invalid UUID guard options" do
    for opts <- [
          [unknown: true],
          [uuid_fields: :yes],
          [uuid_primary_keys: nil],
          [uuid_version: 6]
        ] do
      assert_raise ArgumentError, fn -> validate(Shared, opts) end
    end
  end

  defp validate(module, opts), do: StructTypes.validate([module], [__ENV__.file], opts)

  defmodule Schema do
    defmacro __using__(_opts) do
      quote do
        use Ecto.Schema
        @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
        @foreign_key_type :binary_id
        import unquote(__MODULE__)
      end
    end

    defmacro owned_fields do
      quote do
        field(:macro_id, :binary_id)
      end
    end
  end

  defmodule Inherited do
    use Schema

    @type t :: %__MODULE__{
            __meta__: term(),
            id: String.t(),
            macro_id: any(),
            virtual_id: binary(),
            owner_id: binary(),
            owner: term(),
            code: String.t(),
            external_id: String.t()
          }
    schema "inherited" do
      owned_fields()
      field(:virtual_id, :binary_id, virtual: true)
      belongs_to(:owner, __MODULE__)
      field(:code, :string)
      field(:external_id, :string)
    end
  end

  defmodule Shared do
    use Schema
    alias Ecto.UUID
    @primary_key false
    @type t :: %__MODULE__{__meta__: term(), owner_id: UUID.t() | nil, owner: term()}
    schema "shared" do
      belongs_to(:owner, __MODULE__, primary_key: true)
    end
  end

  defmodule Natural do
    use Ecto.Schema
    @primary_key {:code, :string, []}
    @type t :: %__MODULE__{__meta__: term(), code: String.t()}
    schema "natural" do
    end
  end

  defmodule Keyless do
    use Ecto.Schema
    @primary_key false
    @type t :: %__MODULE__{__meta__: term(), code: String.t()}
    schema "keyless" do
      field(:code, :string)
    end
  end

  defmodule Embedded do
    use Ecto.Schema
    @type t :: %__MODULE__{id: String.t(), external_id: String.t()}
    embedded_schema do
      field(:external_id, :string)
    end
  end

  defmodule EmbeddedForm do
    use Ecto.Schema
    @primary_key false
    @type t :: %__MODULE__{virtual_id: Ecto.UUID.t() | nil}
    embedded_schema do
      field(:virtual_id, :binary_id, virtual: true)
    end
  end

  defmodule VersionSeven do
    use Schema
    @type t :: %__MODULE__{__meta__: term(), id: Ecto.UUID.t()}
    schema "seven" do
    end
  end

  defmodule VersionFour do
    use Ecto.Schema
    @primary_key {:id, Ecto.UUID, autogenerate: true}
    @type t :: %__MODULE__{__meta__: term(), id: Ecto.UUID.t()}
    schema "four" do
    end
  end

  defmodule Composite do
    use Ecto.Schema
    @primary_key false
    @type t :: %__MODULE__{__meta__: term(), owner_id: Ecto.UUID.t(), code: String.t()}
    schema "composite" do
      field(:owner_id, :binary_id, primary_key: true)
      field(:code, :string, primary_key: true)
    end
  end

  defmodule NativeGenerated do
    use Ecto.Schema
    @primary_key {:id, Ecto.UUID, autogenerate: {Ecto.UUID, :generate, [[version: 7]]}}
    @type t :: %__MODULE__{__meta__: term(), id: Ecto.UUID.t()}
    schema "native" do
    end
  end

  defmodule CustomGenerated do
    use Ecto.Schema
    @primary_key {:id, Ecto.UUID, autogenerate: {__MODULE__, :generate, []}}
    @type t :: %__MODULE__{__meta__: term(), id: Ecto.UUID.t()}
    schema "custom" do
    end

    @doc false
    @spec generate() :: Ecto.UUID.t()
    def generate, do: raise("audit must never execute custom generators")
  end

  defmodule AdapterGenerated do
    use Ecto.Schema
    @primary_key {:id, :binary_id, autogenerate: true}
    @type t :: %__MODULE__{__meta__: term(), id: Ecto.UUID.t()}
    schema "adapter" do
    end
  end
end
