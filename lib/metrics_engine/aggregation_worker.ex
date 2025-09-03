defmodule MetricsEngine.AggregationWorker do
  use GenServer
  alias MetricsEngine.Util

  def start_link(opts) do
    metric_name = Keyword.fetch!(opts, :metric_name)
    window = Keyword.fetch!(opts, :window)
    name = {:via, Registry, {MetricsEngine.Registry, {metric_name, window}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    size = Keyword.fetch!(opts, :size)

    tab =
      :ets.new(:metrics_ring, [:set, :protected, read_concurrency: true, write_concurrency: false])

    # Start a cleanup process to clean stale entries.
    Process.send_after(self(), :cleanup, :timer.seconds(1))

    {:ok, %{size: size, tab: tab}}
  end

  @impl true
  def handle_cast({:record, metric}, %{size: size} = state) do
    metric = normalize_metric(metric)
    now = System.system_time(:second)

    if metric.timestamp <= now and now - metric.timestamp < size do
      do_record_metric(metric, state)
    end

    {:noreply, state}
  end

  defp do_record_metric(metric, %{tab: tab, size: size}) do
    %{value: val, timestamp: timestamp, tags: tags} = metric

    keys = Util.powersets(tags)
    idx = rem(timestamp, size)

    for tk <- keys do
      key = {idx, tk}

      case :ets.lookup(tab, key) do
        [] ->
          :ets.insert(tab, {key, timestamp, 1, val, val, val})

        [{^key, ^timestamp, count, sum, mn, mx}] ->
          mn = Util.agg_min(mn, val)
          mx = Util.agg_max(mx, val)
          :ets.insert(tab, {key, timestamp, count + 1, sum + val, mn, mx})

        [{^key, _old_timestamp, _count, _sum, _mn, _mx}] ->
          :ets.insert(tab, {key, timestamp, 1, val, val, val})
      end
    end
  end

  @impl true
  def handle_call({:get, tags}, _from, %{size: size, tab: tab} = st) do
    now = System.system_time(:second)
    tk = Enum.sort(tags)

    {count, sum, minv, maxv} =
      Enum.reduce(0..(size - 1), {0, 0.0, :infinity, :neg_infinity}, fn off, acc ->
        idx = rem(now - off, size)
        key = {idx, tk}

        case :ets.lookup(tab, key) do
          [{^key, ts, c1, s1, mn1, mx1}] when ts <= now and now - ts < size ->
            {c0, s0, mn0, mx0} = acc
            {c0 + c1, s0 + s1, Util.agg_min(mn0, mn1), Util.agg_max(mx0, mx1)}

          _ ->
            acc
        end
      end)

    result =
      if count == 0 do
        %{count: 0, sum: 0.0, avg: nil, min: nil, max: nil}
      else
        %{count: count, sum: sum, avg: sum / count, min: minv, max: maxv}
      end

    {:reply, result, st}
  end

  def handle_call(:ping, _from, st), do: {:reply, :pong, st}

  def handle_call(:reset, _from, st) do
    :ets.delete_all_objects(st.tab)
    {:reply, :ok, st}
  end

  @impl true
  def handle_info(:cleanup, %{size: size, tab: tab} = st) do
    cutoff = System.system_time(:second) - size

    # Delete any entry whose stored timestamp is at or before the cutoff
    ms = [{{{:_, :_}, :"$1", :_, :_, :_, :_}, [{:"=<", :"$1", cutoff}], [true]}]
    :ets.select_delete(tab, ms)

    Process.send_after(self(), :cleanup, :timer.seconds(1))

    {:noreply, st}
  end

  # Helpers

  defp normalize_metric(metric) do
    metric
    |> Map.put_new(:tags, %{})
    |> timestamp_to_integer()
  end

  defp timestamp_to_integer(%{timestamp: ts} = metric) when is_integer(ts), do: metric

  defp timestamp_to_integer(%{timestamp: %DateTime{} = dt} = metric),
    do: Map.put(metric, :timestamp, DateTime.to_unix(dt, :second))

  defp timestamp_to_integer(metric), do: Map.put(metric, :timestamp, System.system_time(:second))
end
