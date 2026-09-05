defmodule ProducerNative do
  @on_load :load
  def load,
    do: :erlang.load_nif(System.fetch_env!("BYLAW_PRODUCER_NIF") |> String.to_charlist(), 0)

  def live_resources, do: :erlang.nif_error(:not_loaded)

  def watch_code_changes(session) do
    for mfa <- [
          {:erlang, :finish_loading, 1},
          {:erlang, :load_module, 2},
          {:erlang, :delete_module, 1}
        ] do
      1 = :trace.function(session, mfa, [{:_, [], [{:message, :producer_code_change}]}], [:local])
    end

    :ok
  end

  def new_slots(_), do: :erlang.nif_error(:not_loaded)
  def plan(_, _, _), do: :erlang.nif_error(:not_loaded)
  def plan(_, _), do: :erlang.nif_error(:not_loaded)
  def integer_list(_), do: :erlang.nif_error(:not_loaded)
  def new(_, _), do: :erlang.nif_error(:not_loaded)
  def new(_), do: :erlang.nif_error(:not_loaded)
  def hits(_), do: :erlang.nif_error(:not_loaded)
  def reasons(_), do: :erlang.nif_error(:not_loaded)
  def status(_), do: :erlang.nif_error(:not_loaded)
  def new, do: :erlang.nif_error(:not_loaded)
  def counts(_), do: :erlang.nif_error(:not_loaded)
  def bytes(_), do: :erlang.nif_error(:not_loaded)
  def enabled(_, _, _), do: :erlang.nif_error(:not_loaded)
  def trace(_, _, _, _, _), do: :erlang.nif_error(:not_loaded)
end
