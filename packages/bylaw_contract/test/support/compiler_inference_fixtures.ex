defmodule Bylaw.Contract.TestFixtures.CompilerInferenceTarget do
  @moduledoc false

  def outcome(flag) when is_boolean(flag) do
    if flag do
      :accepted
    else
      {:error, :rejected}
    end
  end
end

defmodule Bylaw.Contract.TestFixtures.CompilerDeterministicTarget do
  @moduledoc false

  def outcome(:accept), do: :accepted
  def outcome(:reject), do: {:error, :rejected}
end

defmodule Bylaw.Contract.TestFixtures.CompilerProtocolTarget do
  @moduledoc false

  defstruct [:name]

  defimpl List.Chars, for: __MODULE__ do
    def to_charlist(target), do: ~c"#{target.name}"
  end
end
