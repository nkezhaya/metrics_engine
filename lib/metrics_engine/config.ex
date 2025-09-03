defmodule MetricsEngine.Config do
  def validate! do
    case Keyword.validate(all(), [:windows]) do
      {:ok, _opts} -> :ok
      {:error, invalid_keys} -> raise ArgumentError, "invalid keys: #{inspect(invalid_keys)}"
    end
  end

  @compile {:inline, [all: 0, fetch!: 2]}

  @spec windows() :: keyword()
  def windows, do: fetch!(:windows, one_minute: 60, five_minute: 300, fifteen_minute: 900)

  defp all, do: Application.get_all_env(:metrics_engine)
  defp fetch!(key, default), do: Application.get_env(:metrics_engine, key, default)
end
