defmodule MetricsEngine.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    case MetricsEngine.start_link() do
      {:ok, pid} -> {:ok, pid}
      error -> error
    end
  end
end
