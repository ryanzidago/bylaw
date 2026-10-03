defmodule Bylaw.Contract.Counters do
  @moduledoc false

  # Runtime recorder called by instrumented functions. Recording runs in the
  # calling process against a :counters array, so it needs no message passing
  # and cannot fall behind. A call after the session ended is a no-op, and
  # recording never raises into the observed function.

  alias Bylaw.Contract.TypeMatcher

  @type descriptor :: %{
          arguments: list({position :: pos_integer(), target()}),
          returns: list(target())
        }

  @typep target ::
           {hit_slot :: pos_integer(), unknown_slot :: pos_integer(), match_type :: term()}

  @doc false
  @spec put_session(
          token :: integer(),
          modules :: %{module() => {:counters.counters_ref(), tuple()}}
        ) :: :ok
  def put_session(token, modules), do: :persistent_term.put({__MODULE__, token}, modules)

  @doc false
  @spec delete_session(token :: integer()) :: boolean()
  def delete_session(token), do: :persistent_term.erase({__MODULE__, token})

  @doc false
  @spec hit(token :: integer(), module :: module(), slot :: pos_integer()) :: :ok
  def hit(token, module, slot) do
    case :persistent_term.get({__MODULE__, token}, nil) do
      %{^module => {counters, _descriptors}} -> :counters.add(counters, slot, 1)
      _no_session -> :ok
    end
  catch
    _kind, _reason -> :ok
  end

  @doc false
  @spec call(
          token :: integer(),
          module :: module(),
          index :: non_neg_integer(),
          arguments :: tuple()
        ) :: :ok
  def call(token, module, index, arguments) do
    case :persistent_term.get({__MODULE__, token}, nil) do
      %{^module => {counters, descriptors}} ->
        %{arguments: targets} = elem(descriptors, index)

        Enum.each(targets, fn {position, target} ->
          record(counters, target, elem(arguments, position - 1))
        end)

      _no_session ->
        :ok
    end
  catch
    _kind, _reason -> :ok
  end

  @doc false
  @spec return(
          token :: integer(),
          module :: module(),
          index :: non_neg_integer(),
          value :: term()
        ) :: :ok
  def return(token, module, index, value) do
    case :persistent_term.get({__MODULE__, token}, nil) do
      %{^module => {counters, descriptors}} ->
        %{returns: targets} = elem(descriptors, index)
        Enum.each(targets, &record(counters, &1, value))

      _no_session ->
        :ok
    end
  catch
    _kind, _reason -> :ok
  end

  defp record(counters, {hit_slot, unknown_slot, match_type}, value) do
    case TypeMatcher.match(value, match_type) do
      :match -> :counters.add(counters, hit_slot, 1)
      :unknown -> :counters.put(counters, unknown_slot, 1)
      :no_match -> :ok
    end
  end
end
