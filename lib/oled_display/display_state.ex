defmodule OledDisplay.DisplayState do
  @moduledoc """
  GenServer that owns the shared ETS table `:oled_display_state`.

  All runtime state that needs to survive screen switches lives here:
  weather cache, system counters, and WiFi mirror.
  """

  use GenServer

  @table :oled_display_state

  # ── Lifecycle ─────────────────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @impl true
  def init([]) do
    :ets.new(@table, [:set, :named_table, :public, {:read_concurrency, true}])
    {:ok, %{}}
  end

  # ── Public API ──────────────────────────────────────────────────

  @spec get(atom(), term(), term()) :: term()
  def get(namespace, key, default \\ nil) do
    case :ets.lookup(@table, {namespace, key}) do
      [{_key, value}] -> value
      [] -> default
    end
  end

  @spec put(atom(), term(), term()) :: :ok
  def put(namespace, key, value) do
    :ets.insert(@table, {{namespace, key}, value})
    :ok
  end

  @spec delete(atom(), term()) :: :ok
  def delete(namespace, key) do
    :ets.delete(@table, {namespace, key})
    :ok
  end

  @spec all(atom()) :: [{term(), term()}]
  def all(namespace) do
    :ets.match(@table, {{namespace, :"$1"}, :"$2"})
    |> Enum.map(fn [k, v] -> {k, v} end)
  end
end
