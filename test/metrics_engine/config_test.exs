defmodule MetricsEngine.ConfigTest do
  use ExUnit.Case, async: false
  alias MetricsEngine.Config

  setup do
    # Snapshot current env and restore after each test
    original = Application.get_all_env(:metrics_engine)

    on_exit(fn ->
      # Clear all keys first
      for {k, _v} <- Application.get_all_env(:metrics_engine),
          do: Application.delete_env(:metrics_engine, k)

      # Restore snapshot
      for {k, v} <- original, do: Application.put_env(:metrics_engine, k, v)
    end)

    :ok
  end

  test "windows/0 returns configured windows" do
    custom = [one_minute: 60, five_minute: 300]
    Application.put_env(:metrics_engine, :windows, custom)

    assert Config.windows() == custom
  end

  test "windows/0 falls back to defaults when unset" do
    Application.delete_env(:metrics_engine, :windows)

    assert Config.windows() == [one_minute: 60, five_minute: 300, fifteen_minute: 900]
  end

  test "validate!/0 passes with only known keys" do
    Application.put_env(:metrics_engine, :windows, one_minute: 60)

    assert :ok == Config.validate!()
  end

  test "validate!/0 raises on unknown keys" do
    Application.put_env(:metrics_engine, :windows, one_minute: 60)
    Application.put_env(:metrics_engine, :unexpected, true)

    assert_raise ArgumentError, fn -> Config.validate!() end
  end
end
