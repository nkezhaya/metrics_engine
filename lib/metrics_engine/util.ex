defmodule MetricsEngine.Util do
  @moduledoc """
  Small helpers used by the aggregation workers.

  These functions implement min/max operations that gracefully handle
  sentinel initial values used during rolling aggregation:
  - `:infinity` for an uninitialized minimum
  - `:neg_infinity` for an uninitialized maximum
  """

  @doc """
  Aggregates a minimum, treating `:infinity` as an identity.

  Examples:

      iex> MetricsEngine.Util.agg_min(:infinity, 7)
      7
      iex> MetricsEngine.Util.agg_min(5, 10)
      5
  """
  @spec agg_min(number() | :infinity, number() | :infinity) :: number()
  def agg_min(:infinity, value), do: value
  def agg_min(value, :infinity), do: value
  def agg_min(a, b), do: min(a, b)

  @doc """
  Aggregates a maximum, treating `:neg_infinity` as an identity.

  Examples:

      iex> MetricsEngine.Util.agg_max(:neg_infinity, 7)
      7
      iex> MetricsEngine.Util.agg_max(5, 10)
      10
  """
  @spec agg_max(number() | :neg_infinity, number() | :neg_infinity) :: number()
  def agg_max(:neg_infinity, value), do: value
  def agg_max(value, :neg_infinity), do: value
  def agg_max(a, b), do: max(a, b)

  @doc """
  Builds the powersets of a tag map as sorted key-value lists.

  - Input is a map of tag pairs, e.g. `%{"b" => "2", "a" => "1"}`.
  - Output is a list of subsets, where each subset is a list of
    `{key, value}` pairs sorted in ascending key order.
  - Includes the empty subset `[]` to support global aggregations.

  Examples:

      iex> MetricsEngine.Util.powersets(%{"b" => "2", "a" => "1"})
      [
        [],
        [{"a", "1"}],
        [{"b", "2"}],
        [{"a", "1"}, {"b", "2"}]
      ]
  """
  @spec powersets(%{optional(String.t()) => String.t()}) :: [[{String.t(), String.t()}]]
  def powersets(%{} = tags) do
    tags
    |> Enum.sort()
    |> Enum.reduce([[]], fn element, acc ->
      acc ++ Enum.map(acc, fn subset -> subset ++ [element] end)
    end)
  end
end
