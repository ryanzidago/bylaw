defmodule Bylaw.Ecto.Query.Boundedness do
  @moduledoc false

  @typep filter_type :: :empty | :restricting | :unrestricting

  @spec root_where_bounded?(term()) :: boolean()
  def root_where_bounded?(%{wheres: wheres}) when is_list(wheres) do
    wheres
    |> Enum.reduce(nil, &combine_where/2)
    |> bounded_filter?()
  end

  def root_where_bounded?(_query), do: false

  @spec combine_where(term(), filter_type() | nil) :: filter_type()
  defp combine_where(%{expr: expr} = where, nil) do
    filter_type(expr, where_params(where))
  end

  defp combine_where(%{expr: expr, op: :or} = where, filter) do
    or_filter(filter, filter_type(expr, where_params(where)))
  end

  defp combine_where(%{expr: expr} = where, filter) do
    and_filter(filter, filter_type(expr, where_params(where)))
  end

  defp combine_where(_where, nil), do: :restricting
  defp combine_where(_where, filter), do: and_filter(filter, :restricting)

  @spec where_params(map()) :: list()
  defp where_params(%{params: params}) when is_list(params), do: params
  defp where_params(_where), do: []

  @spec filter_type(term(), list()) :: filter_type()
  defp filter_type(true, _params), do: :unrestricting
  defp filter_type(false, _params), do: :empty

  defp filter_type({:^, _meta, [index]}, params) when is_integer(index) do
    case Enum.fetch(params, index) do
      {:ok, {value, _type}} -> filter_type(value, [])
      {:ok, value} -> filter_type(value, [])
      :error -> :restricting
    end
  end

  defp filter_type(%Ecto.Query.Tagged{value: value}, _params), do: filter_type(value, [])
  defp filter_type({:type, _meta, [expr, _type]}, params), do: filter_type(expr, params)

  defp filter_type({:and, _meta, [left, right]}, params) do
    left
    |> filter_type(params)
    |> and_filter(filter_type(right, params))
  end

  defp filter_type({:or, _meta, [left, right]}, params) do
    left
    |> filter_type(params)
    |> or_filter(filter_type(right, params))
  end

  defp filter_type({:not, _meta, [expr]}, params) do
    expr
    |> filter_type(params)
    |> negate_filter()
  end

  defp filter_type(_expr, _params), do: :restricting

  @spec and_filter(filter_type(), filter_type()) :: filter_type()
  defp and_filter(:empty, _right), do: :empty
  defp and_filter(_left, :empty), do: :empty
  defp and_filter(:unrestricting, :unrestricting), do: :unrestricting
  defp and_filter(_left, _right), do: :restricting

  @spec or_filter(filter_type(), filter_type()) :: filter_type()
  defp or_filter(:unrestricting, _right), do: :unrestricting
  defp or_filter(_left, :unrestricting), do: :unrestricting
  defp or_filter(:empty, :empty), do: :empty
  defp or_filter(_left, _right), do: :restricting

  @spec negate_filter(filter_type()) :: filter_type()
  defp negate_filter(:unrestricting), do: :empty
  defp negate_filter(:empty), do: :unrestricting
  defp negate_filter(:restricting), do: :restricting

  @spec bounded_filter?(filter_type() | nil) :: boolean()
  defp bounded_filter?(nil), do: false
  defp bounded_filter?(:unrestricting), do: false
  defp bounded_filter?(_filter), do: true
end
