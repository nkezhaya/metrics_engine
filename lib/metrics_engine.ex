defmodule MetricsEngine do
  alias __MODULE__.Config
  require Logger

  @type metric() :: %{
          required(:metric_name) => String.t(),
          required(:value) => number(),
          optional(:timestamp) => DateTime.t() | pos_integer(),
          optional(:tags) => %{String.t() => String.t()}
        }

  @type aggregation() :: %{
          required(:count) => nil | number(),
          required(:sum) => nil | number(),
          required(:avg) => nil | number(),
          required(:min) => nil | number(),
          required(:max) => nil | number()
        }

  @type window() :: atom()

  @doc """
  Add a metric point.

  Expects: %{metric_name: binary, value: float, timestamp: integer | DateTime, tags: map()}
  """
  @spec record_metric(metric()) :: :ok
  def record_metric(%{metric_name: metric_name} = metric) do
    for {window, _size} <- Config.windows() do
      ensure_worker(metric_name, window)
      GenServer.cast(via_name(metric_name, window), {:record, metric})
    end

    :ok
  end

  @doc """
  Returns the aggregated values for the given metric name and window.
  Optionally, you can pass in tags to filter by.

  ## Example

      get_aggregations("api.response_time", :one_minute)
      # => %{count: 100, sum: 15050.0, avg: 150.5, min: 50.0, max: 300.0}

      get_aggregations("api.response_time", :one_minute, %{"service" => "web"})
      # => %{count: 80, sum: 13048.0, avg: 150.5, min: 50.0, max: 300.0}
  """
  @spec get_aggregations(String.t(), window(), map()) :: aggregation()
  def get_aggregations(metric_name, window, tags \\ %{}) do
    case Registry.lookup(MetricsEngine.Registry, {metric_name, window}) do
      [{pid, _}] when is_pid(pid) ->
        GenServer.call(pid, {:get, tags})

      _ ->
        # unknown metric/window -> empty result
        %{count: 0, sum: 0.0, avg: nil, min: nil, max: nil}
    end
  end

  @doc """
  Starts the MetricsEngine supervision tree (Registry + DynamicSupervisor).
  Safe to call multiple times; returns existing supervisor if already started.
  """
  def start_link do
    case Process.whereis(MetricsEngine.Supervisor) do
      pid when is_pid(pid) ->
        {:ok, pid}

      _ ->
        Config.validate!()

        children = [
          {Registry, keys: :unique, name: MetricsEngine.Registry},
          {DynamicSupervisor, strategy: :one_for_one, name: MetricsEngine.WorkerSupervisor}
        ]

        Supervisor.start_link(children, strategy: :one_for_one, name: MetricsEngine.Supervisor)
    end
  end

  defp via_name(metric_name, window),
    do: {:via, Registry, {MetricsEngine.Registry, {metric_name, window}}}

  defp ensure_worker(metric_name, window) do
    case Registry.lookup(MetricsEngine.Registry, {metric_name, window}) do
      [{pid, _}] when is_pid(pid) ->
        {:ok, pid}

      _ ->
        args = [
          metric_name: metric_name,
          window: window,
          size: Keyword.fetch!(Config.windows(), window)
        ]

        spec = %{
          id: {MetricsEngine.AggregationWorker, {metric_name, window}},
          start: {MetricsEngine.AggregationWorker, :start_link, [args]},
          restart: :transient,
          shutdown: 5_000,
          type: :worker
        }

        case DynamicSupervisor.start_child(MetricsEngine.WorkerSupervisor, spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          error -> error
        end
    end
  end
end
