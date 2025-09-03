# MetricsEngine

A real-time metrics aggregation engine using Elixir/OTP. It ingests metric points and maintains rolling-window aggregations (count, sum, average, min, max) over configurable windows (1m, 5m, 15m by default), with tag-based grouping and bounded memory via ETS-backed ring buffers.

See ARCHITECTURE.md for a deeper dive into the design.

## Quickstart

Start the supervision tree, record some metrics, and query aggregations:

```elixir
{:ok, _pid} = MetricsEngine.start_link()

MetricsEngine.record_metric(%{
  metric_name: "api.response_time",
  value: 150.5,
  timestamp: DateTime.utc_now(),
  tags: %{"service" => "web", "environment" => "prod"}
})

# Global aggregations for the 1-minute window
MetricsEngine.get_aggregations("api.response_time", :one_minute)
#=> %{count: 1, sum: 150.5, avg: 150.5, min: 150.5, max: 150.5}

# Filtered by tags (conjunctive semantics)
MetricsEngine.get_aggregations("api.response_time", :five_minute, %{"service" => "web"})
```

Notes:
- `timestamp` can be a `DateTime` or a Unix second (integer). If omitted, current time is used.
- Future-dated points are ignored. Exactly window-old points are excluded for that window (strict `< window_size`).
- Tag filters are conjunctive: only points whose tags map contains all requested pairs contribute.

## Configuration

Configure window sizes (in seconds) via `config/config.exs`:

```elixir
import Config

config :metrics_engine,
  windows: [one_minute: 60, five_minute: 300, fifteen_minute: 900]
```

Windows are identified by atom keys in this keyword list. New keys imply new workers will be spawned lazily on first use for each metric.

## Running Tests

```bash
mix test
```

The test suite covers correctness for basic stats, tag semantics, window boundaries, concurrent ingestion, crash/restart behavior, and unknown-metric queries.

## Design Overview

- Dynamic workers: one `GenServer` per `{metric_name, window}` combination.
- Registry: routes metric events to the correct worker via `{:via, Registry, ...}` names.
- ETS-backed ring buffer: per-second buckets with timestamp guards to maintain rolling windows in bounded memory.
- Cleanup: periodic pruning of stale buckets and validation at read time to ensure accuracy.

For details on components, data flow, and trade-offs, see ARCHITECTURE.md.
