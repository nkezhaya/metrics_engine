# Architecture

This document explains the OTP architecture, data structures, and trade-offs behind MetricsEngine.

## Goals

- Real-time rolling aggregations over multiple time windows.
- Concurrency-safe ingestion with bounded memory usage.
- Flexible tag-based grouping (conjunctive filters and global totals).
- Resilient OTP design with isolated failures.

## Components

### Supervision Tree

- `MetricsEngine.Supervisor` (top-level): starts
  - `Registry` (`MetricsEngine.Registry`) with `:unique` keys for worker routing
  - `DynamicSupervisor` (`MetricsEngine.WorkerSupervisor`) with `:one_for_one` strategy

Workers are started lazily per `{metric_name, window}` on first ingestion.

### Aggregation Workers

- One `GenServer` per `{metric_name, window}` pair: `MetricsEngine.AggregationWorker`.
- Name: `{:via, Registry, {MetricsEngine.Registry, {metric_name, window}}}` allowing lookup and de-duplication.
- State:
  - `size`: window size in seconds (e.g., 60 for `:one_minute`)
  - `tab`: an ETS table (`:set`) holding per-second buckets keyed by index and tag subset

### ETS Ring Buffer

Each worker maintains a ring buffer of `size` per-second buckets. For an incoming metric with Unix second `timestamp` and tags `tags`:

1. Compute `idx = rem(timestamp, size)`.
2. Generate all sorted tag-subsets including the empty set (for global totals).
3. For each subset `tk`, key is `{idx, tk}`. Insert or update a row of shape:
   `{ {idx, tk}, timestamp, count, sum, min, max }`.

Timestamp is stored with each bucket. On write, if the stored timestamp matches this `timestamp`, we aggregate into the same bucket; otherwise we overwrite the bucket (reset) to avoid stale carryover when the ring wraps.

### Cleanup and Expiration

- Periodic task (`:cleanup` every second) deletes any ETS entries whose stored `timestamp <= now - size`.
- Read-time checks also verify `now - ts < size` to guard against any lingering stale rows.

## Data Flow

### Ingestion (`MetricsEngine.record_metric/1`)

1. For each configured window in `MetricsEngine.Config.windows/0`, ensure a worker exists (spawn via `DynamicSupervisor` if necessary).
2. `GenServer.cast` the metric to the worker.
3. Worker normalizes the metric (ensures `timestamp` and default `%{}` tags), rejects future points, and writes to its ETS ring across all tag-subsets.

### Query (`MetricsEngine.get_aggregations/3`)

1. Lookup worker via `Registry` for `{metric_name, window}`.
2. If present, `GenServer.call` with the requested tags map.
3. Worker sorts the tag filter into a canonical list and scans the `size` indices `[0..size-1]` computing the aggregate from valid buckets.

## Complexity & Memory

- Write: O(2^t) per metric where `t` is number of tag pairs in the event (due to subset indexing). This enables fast and flexible queries but can amplify writes when events have many tags.
- Read: O(W) bucket lookups per query, where `W` is window size in seconds (60–900 by default). With `read_concurrency: true`, ETS provides fast lookups.
- Memory: bounded by `W * number_of_unique_tag_subsets_touched`. Periodic cleanup prevents unbounded growth.

## Failure Handling

- Each worker is isolated; crashes affect only its metric/window.
- `DynamicSupervisor` restarts workers. State is ephemeral (ETS is per-process), which is acceptable for in-memory rolling windows.

## Time Semantics

- Reject future timestamps.
- An event contributes to a window iff `now - timestamp < window_size`. Exactly `window_size` seconds old is excluded for that window but will be included by larger windows.

## Configuration

Define window sizes (seconds) in `config/config.exs`:

```elixir
config :metrics_engine,
  windows: [one_minute: 60, five_minute: 300, fifteen_minute: 900]
```

Updating this list adds/removes window types globally. Workers are created lazily upon first ingestion for a metric.

## Trade-offs and Future Work

- Subset indexing is powerful but can be expensive for events with many tags. Potential alternatives:
  - Configure allowed tag dimensions (e.g., only index `service`, `environment`).
  - Use a separate aggregation process per tag-dimension to cap subset growth.
- Query performance can be improved by maintaining rolling aggregates (incremental snapshots) to avoid scanning all `W` buckets at read-time (trade-off: extra write-time work and complexity).
- Add input validation and instrumentation (Telemetry) for operational visibility.

