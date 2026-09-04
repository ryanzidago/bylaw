defmodule Bylaw.Contract.TestFixtures.RemoteTypes do
  @moduledoc false

  @type role :: :admin | :member
  @opaque token :: binary()
end

defmodule Bylaw.Contract.TestFixtures.SpecTarget do
  @moduledoc false

  alias Bylaw.Contract.TestFixtures.RemoteTypes

  @type audience :: RemoteTypes.role() | {:guest, non_neg_integer()}
  @type channel :: :web | pos_integer() | number() | RemoteTypes.token()

  @spec observe(audience :: audience(), channel :: channel()) :: {audience(), channel()}
  def observe(audience, channel), do: {audience, channel}
end

defmodule Bylaw.Contract.TestFixtures.User do
  @moduledoc false

  defstruct [:id]

  @type t :: %__MODULE__{id: pos_integer()}
end

defmodule Bylaw.Contract.TestFixtures.Registration do
  @moduledoc false

  alias Bylaw.Contract.TestFixtures.User

  @spec register(age :: non_neg_integer()) :: {:ok, User.t()} | {:error, :underage}
  def register(age) when age >= 18, do: {:ok, %User{id: age}}
  def register(_age), do: {:error, :underage}
end

defmodule Bylaw.Contract.TestFixtures.UnsupportedReturn do
  @moduledoc false

  alias Bylaw.Contract.TestFixtures.RemoteTypes

  @spec token(success? :: boolean()) :: :ok | RemoteTypes.token()
  def token(true), do: :ok
  def token(false), do: "opaque token"
end
