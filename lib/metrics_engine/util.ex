defmodule MetricsEngine.Util do
  def agg_min(:infinity, value), do: value
  def agg_min(value, :infinity), do: value
  def agg_min(a, b), do: min(a, b)

  def agg_max(:neg_infinity, value), do: value
  def agg_max(value, :neg_infinity), do: value
  def agg_max(a, b), do: max(a, b)
end
