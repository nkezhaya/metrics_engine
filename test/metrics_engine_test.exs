defmodule MetricsEngineTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, _} = MetricsEngine.start_link()
    reset()
    :ok
  end

  test "spawns workers on demand and aggregates basic stats" do
    ts = now()

    MetricsEngine.record_metric(%{
      metric_name: "api.response_time",
      value: 100.0,
      timestamp: ts,
      tags: %{}
    })

    MetricsEngine.record_metric(%{
      metric_name: "api.response_time",
      value: 300.0,
      timestamp: ts,
      tags: %{}
    })

    flush()
    agg = MetricsEngine.get_aggregations("api.response_time", :one_minute)
    assert %{count: 2, sum: 400.0, avg: 200.0, min: 100.0, max: 300.0} = agg

    assert MetricsEngine.get_aggregations("api.response_time", :five_minute) == agg
  end

  test "conjunctive tag semantics (subset filter)" do
    ts = now()

    MetricsEngine.record_metric(%{
      metric_name: "api.response_time",
      value: 500.0,
      timestamp: ts,
      tags: %{"service" => "web", "env" => "prod"}
    })

    MetricsEngine.record_metric(%{
      metric_name: "api.response_time",
      value: 600.0,
      timestamp: ts,
      tags: %{"service" => "web", "env" => "test"}
    })

    flush()

    # Global
    assert %{count: 2, sum: 1100.0, avg: 550.0, min: 500.0, max: 600.0} =
             MetricsEngine.get_aggregations("api.response_time", :one_minute)

    # service=web (both contribute)
    assert %{count: 2, sum: 1100.0, avg: 550.0, min: 500.0, max: 600.0} =
             MetricsEngine.get_aggregations("api.response_time", :one_minute, %{
               "service" => "web"
             })

    # env=prod (only first)
    assert %{count: 1, sum: 500.0, avg: 500.0, min: 500.0, max: 500.0} =
             MetricsEngine.get_aggregations("api.response_time", :one_minute, %{"env" => "prod"})

    # service=web AND env=test (only second)
    assert %{count: 1, sum: 600.0, avg: 600.0, min: 600.0, max: 600.0} =
             MetricsEngine.get_aggregations("api.response_time", :one_minute, %{
               "service" => "web",
               "env" => "test"
             })

    # Mismatch should be zero
    assert %{count: 0, sum: +0.0, avg: nil, min: nil, max: nil} =
             MetricsEngine.get_aggregations("api.response_time", :one_minute, %{
               "service" => "web",
               "env" => "staging"
             })
  end

  test "older-than-window data is excluded for :one_minute but included for :five_minute" do
    old_ts = now() - 100

    MetricsEngine.record_metric(%{
      metric_name: "latency",
      value: 50.0,
      timestamp: old_ts,
      tags: %{}
    })

    cur_ts = now()

    MetricsEngine.record_metric(%{
      metric_name: "latency",
      value: 150.0,
      timestamp: cur_ts,
      tags: %{}
    })

    flush()

    # one_minute should see only the current point
    assert %{count: 1, sum: 150.0, avg: 150.0, min: 150.0, max: 150.0} =
             MetricsEngine.get_aggregations("latency", :one_minute)

    # five_minute should see both
    assert %{count: 2, sum: 200.0, avg: 100.0, min: 50.0, max: 150.0} =
             MetricsEngine.get_aggregations("latency", :five_minute)
  end

  test "future-dated data is excluded from all windows" do
    ts_future = now() + 5

    MetricsEngine.record_metric(%{
      metric_name: "future",
      value: 42.0,
      timestamp: ts_future,
      tags: %{}
    })

    flush()

    # No contribution since event is in the future
    assert %{count: 0, sum: +0.0, avg: nil, min: nil, max: nil} =
             MetricsEngine.get_aggregations("future", :one_minute)

    assert %{count: 0, sum: +0.0, avg: nil, min: nil, max: nil} =
             MetricsEngine.get_aggregations("future", :five_minute)

    assert %{count: 0, sum: +0.0, avg: nil, min: nil, max: nil} =
             MetricsEngine.get_aggregations("future", :fifteen_minute)
  end

  test "exactly window-old data excluded for that window, included for larger ones" do
    # Exactly 60s old: excluded from :one_minute, included in larger windows
    ts_edge = now() - 60

    MetricsEngine.record_metric(%{
      metric_name: "edge",
      value: 7.0,
      timestamp: ts_edge,
      tags: %{}
    })

    flush()

    assert %{count: 0, sum: +0.0, avg: nil, min: nil, max: nil} =
             MetricsEngine.get_aggregations("edge", :one_minute)

    assert %{count: 1, sum: 7.0, avg: 7.0, min: 7.0, max: 7.0} =
             MetricsEngine.get_aggregations("edge", :five_minute)

    assert %{count: 1, sum: 7.0, avg: 7.0, min: 7.0, max: 7.0} =
             MetricsEngine.get_aggregations("edge", :fifteen_minute)
  end

  test "min/max across buckets" do
    ts = now()

    MetricsEngine.record_metric(%{metric_name: "temp", value: 9.0, timestamp: ts, tags: %{}})
    MetricsEngine.record_metric(%{metric_name: "temp", value: 1.0, timestamp: ts, tags: %{}})
    MetricsEngine.record_metric(%{metric_name: "temp", value: 5.0, timestamp: ts, tags: %{}})

    flush()

    assert %{count: 3, sum: 15.0, avg: 5.0, min: 1.0, max: 9.0} =
             MetricsEngine.get_aggregations("temp", :one_minute)
  end

  test "avg derived from sum/count with binary-exact fractions" do
    ts = now()

    # 0.25, 0.50, 0.75 are binary-exact; avoids flaky float comparisons
    MetricsEngine.record_metric(%{metric_name: "cpu", value: 0.25, timestamp: ts, tags: %{}})
    MetricsEngine.record_metric(%{metric_name: "cpu", value: 0.50, timestamp: ts, tags: %{}})
    MetricsEngine.record_metric(%{metric_name: "cpu", value: 0.75, timestamp: ts, tags: %{}})

    flush()

    assert %{count: 3, sum: 1.5, avg: 0.5, min: 0.25, max: 0.75} =
             MetricsEngine.get_aggregations("cpu", :one_minute)
  end

  test "concurrent ingestion is serialized by the worker (await tasks, then call)" do
    ts = now()
    n = 150

    tasks =
      for _ <- 1..n do
        Task.async(fn ->
          MetricsEngine.record_metric(%{
            metric_name: "qps",
            value: 1.0,
            timestamp: ts,
            tags: %{"service" => "api"}
          })
        end)
      end

    Enum.each(tasks, &Task.await(&1, 5_000))

    flush()

    assert %{count: 150, sum: 150.0, avg: 1.0, min: 1.0, max: 1.0} =
             MetricsEngine.get_aggregations("qps", :one_minute, %{"service" => "api"})
  end

  test "worker is restarted on crash; state is ephemeral" do
    ts = now()

    # Ensure worker exists and has state
    MetricsEngine.record_metric(%{metric_name: "errs", value: 1.0, timestamp: ts, tags: %{}})

    # Kill the one_minute worker for this metric
    [{pid, _}] = Registry.lookup(MetricsEngine.Registry, {"errs", :one_minute})
    assert is_pid(pid)
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, _proc, _obj, _reason}, 1_000

    # Wait for restart (same name via Registry)
    new_pid =
      Stream.repeatedly(fn -> Registry.lookup(MetricsEngine.Registry, {"errs", :one_minute}) end)
      |> Enum.find_value(fn
        [{npid, _}] when is_pid(npid) and npid != pid -> npid
        _ -> false
      end)

    assert is_pid(new_pid)

    # State should be empty
    assert %{count: 0, sum: +0.0, avg: nil, min: nil, max: nil} =
             MetricsEngine.get_aggregations("errs", :one_minute)
  end

  test "querying unknown metric/window returns empty result (lazy worker start)" do
    assert %{count: 0, sum: +0.0, avg: nil, min: nil, max: nil} =
             MetricsEngine.get_aggregations("unknown.metric", :one_minute, %{"env" => "prod"})
  end

  test "global subset counted exactly once" do
    ts = now()

    MetricsEngine.record_metric(%{
      metric_name: "io",
      value: 10.0,
      timestamp: ts,
      tags: %{"a" => "1"}
    })

    flush()

    assert %{count: 1, sum: 10.0, avg: 10.0, min: 10.0, max: 10.0} =
             MetricsEngine.get_aggregations("io", :one_minute)
  end

  defp now(), do: System.system_time(:second)

  defp flush do
    Enum.map(worker_pids(), &GenServer.call(&1, :ping))
  end

  defp reset do
    Enum.map(worker_pids(), &GenServer.call(&1, :reset))
  end

  defp worker_pids do
    MetricsEngine.WorkerSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_, pid, _, _} -> pid end)
  end
end
