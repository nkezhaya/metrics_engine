defmodule MetricsEngine.UtilTest do
  use ExUnit.Case, async: true
  alias MetricsEngine.Util

  test "agg_min handles :infinity and numbers" do
    assert Util.agg_min(:infinity, 7) == 7
    assert Util.agg_min(7, :infinity) == 7
    assert Util.agg_min(5, 10) == 5
    assert Util.agg_min(10, 5) == 5
  end

  test "agg_max handles :neg_infinity and numbers" do
    assert Util.agg_max(:neg_infinity, 7) == 7
    assert Util.agg_max(7, :neg_infinity) == 7
    assert Util.agg_max(5, 10) == 10
    assert Util.agg_max(10, 5) == 10
  end
end

