defmodule Bylaw.Contract.FunctionSelection do
  @moduledoc false

  @type t :: :all | MapSet.t(Bylaw.Contract.Check.observed_mfa())

  @doc false
  @spec new!(selection :: term(), modules :: list(module())) ::
          MapSet.t(Bylaw.Contract.Check.observed_mfa())
  def new!(selection, modules) do
    unless is_list(selection) and Enum.all?(selection, &valid_mfa?/1) do
      raise ArgumentError,
            "expected :only to be a list of {module, function, arity} tuples with arity in 0..255"
    end

    supplied = MapSet.new(modules)

    for {module, _, _} <- selection, not MapSet.member?(supplied, module) do
      raise ArgumentError, "selected module #{inspect(module)} is not in the supplied modules"
    end

    MapSet.new(selection)
  end

  @doc false
  @spec modules(modules :: list(module()), selection :: t()) :: list(module())
  def modules(modules, :all), do: modules

  def modules(modules, selection) do
    selected = MapSet.new(selection, &elem(&1, 0))
    Enum.filter(modules, &MapSet.member?(selected, &1))
  end

  @doc false
  @spec member?(selection :: t(), module :: module(), function :: atom(), arity :: arity()) ::
          boolean()
  def member?(:all, _module, _function, _arity), do: true

  def member?(selection, module, function, arity),
    do: MapSet.member?(selection, {module, function, arity})

  defp valid_mfa?({module, function, arity}),
    do:
      is_atom(module) and is_atom(function) and is_integer(arity) and arity >= 0 and arity <= 255

  defp valid_mfa?(_), do: false
end
