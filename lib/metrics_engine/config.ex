defmodule MetricsEngine.Config do
  @moduledoc """
  Configuration access for MetricsEngine.

  This module provides a thin layer over `Application.get_env/3` to
  fetch engine configuration and a validator to ensure only supported
  keys are present. Today, only the `:windows` key is supported.

  Windows are defined as a keyword list mapping window-name atoms to
  their sizes in seconds, for example:

      [one_minute: 60, five_minute: 300, fifteen_minute: 900]

  Missing configuration falls back to the defaults above.
  """

  @doc """
  Validates that only supported configuration keys are present.

  Returns `:ok` on success, raises `ArgumentError` if unknown keys are
  found in the `:metrics_engine` application environment.
  """
  @spec validate!() :: :ok
  def validate! do
    case Keyword.validate(all(), [:windows]) do
      {:ok, _opts} -> :ok
      {:error, invalid_keys} -> raise ArgumentError, "invalid keys: #{inspect(invalid_keys)}"
    end
  end

  @compile {:inline, [all: 0, fetch!: 2]}

  @doc """
  Returns the configured windows as a keyword list of `{name, seconds}`.

  Falls back to the default windows when `:windows` is not set:

      [one_minute: 60, five_minute: 300, fifteen_minute: 900]
  """
  @spec windows() :: keyword()
  def windows, do: fetch!(:windows, one_minute: 60, five_minute: 300, fifteen_minute: 900)

  defp all, do: Application.get_all_env(:metrics_engine)
  defp fetch!(key, default), do: Application.get_env(:metrics_engine, key, default)
end
