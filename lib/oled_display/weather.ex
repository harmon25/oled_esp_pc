defmodule OledDisplay.Weather do
  @compile {:no_warn_undefined, [:avm_pubsub, :atomvm]}

  require OledDisplay.Log
  alias OledDisplay.Log

  @moduledoc """
  GenServer that fetches weather from wttr.in and caches it in ETS.

  - Seeds ETS on init with configured locations and :pending entries.
  - Subscribes to WiFi status and starts fetching on :connected.
  - Publishes {:weather_data, name} after every successful fetch.
  - Publishes {:weather_ready, name} on the *first* success per location.

  Fetches locations **sequentially** in a spawned task — one TCP socket
  at a time — to keep peak heap usage on the ESP32-C3 small. See
  `OledDisplay.Weather.Client` for the wire protocol.
  """

  use GenServer

  alias OledDisplay.DisplayState
  alias OledDisplay.Weather.Client

  @default_fetch_interval_ms 900_000

  @weather_cfg Application.compile_env(:oled_display, :weather, [])
  @locations Keyword.get(@weather_cfg, :locations, [])
  @units Keyword.get(@weather_cfg, :units, :celsius)
  @fetch_interval_ms Keyword.get(@weather_cfg, :fetch_interval_ms, @default_fetch_interval_ms)

  # ── Lifecycle ───────────────────────────────────────────────────

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
    :avm_pubsub.sub(:pubsub, [:wifi_wiz, :wifi_status])

    # Seed ETS
    DisplayState.put(:weather, :locations, @locations)
    DisplayState.put(:weather, :units, @units)

    for loc <- @locations do
      DisplayState.put(:weather, {:loc, loc.name}, %{
        status: :pending,
        temp: 0.0,
        humidity: 0,
        icon: :cloud,
        is_day: 1,
        fetched_at: 0
      })
    end

    {wifi_connected, _ip, _ap_ssid} = OledDisplay.WiFi.status()

    state = %{
      locations: @locations,
      units: @units,
      interval: @fetch_interval_ms,
      wifi_connected: wifi_connected,
      fetch_timer: nil,
      ready_set: MapSet.new()
    }

    # If WiFi is already up and we have something to fetch, kick off the
    # first request after a short delay so a crash-loop doesn't hammer
    # the network. Otherwise wait for :wifi_status -> :connected.
    if wifi_connected and @locations != [] do
      Log.debug("Weather", "wifi already up, deferring first fetch 3 s")
      timer_ref = Process.send_after(self(), :fetch_all, 3_000)
      {:ok, %{state | fetch_timer: timer_ref}}
    else
      {:ok, state}
    end
  end

  # ── Public API ──────────────────────────────────────────────────

  def force_refresh do
    GenServer.cast(__MODULE__, :fetch_all)
  end

  # ── GenServer callbacks ──────────────────────────────────────────

  @impl true
  def handle_cast(:fetch_all, state) do
    new_state = do_fetch_all(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:pub, [:wifi_wiz, :wifi_status], _from, {:connected, _ip}}, state) do
    Log.debug("Weather", "pub wifi_status connected, starting fetches")
    new_state = %{state | wifi_connected: true}
    {:noreply, do_fetch_all(new_state)}
  end

  def handle_info({:pub, [:wifi_wiz, :wifi_status], _from, {:ap_mode, _ssid}}, state) do
    Log.debug("Weather", "pub wifi_status ap_mode, pausing fetches")
    {:noreply, cancel_timer(%{state | wifi_connected: false})}
  end

  def handle_info({:pub, [:wifi_wiz, :wifi_status], _from, status}, state) do
    Log.debugf("Weather", "pub wifi_status status=~p, pausing fetches", [status])
    {:noreply, cancel_timer(%{state | wifi_connected: false})}
  end

  def handle_info(:fetch_all, state) do
    new_state =
      if state.wifi_connected do
        do_fetch_all(state)
      else
        cancel_timer(state)
      end

    {:noreply, new_state}
  end

  def handle_info({:fetched, name, {:ok, payload}}, state) do
    Log.debugf("Weather", "fetched ~s ok", [name])
    DisplayState.put(:weather, {:loc, name}, Map.put(payload, :status, :ok))
    :avm_pubsub.pub(:pubsub, [:weather_data], name)

    new_ready_set =
      if MapSet.member?(state.ready_set, name) do
        state.ready_set
      else
        Log.debugf("Weather", "first fetch for ~s, publishing weather_ready", [name])
        :avm_pubsub.pub(:pubsub, [:weather_ready], name)
        MapSet.put(state.ready_set, name)
      end

    {:noreply, %{state | ready_set: new_ready_set}}
  end

  def handle_info({:fetched, name, {:error, reason}}, state) do
    Log.debugf("Weather", "fetched ~s error=~p", [name, reason])
    existing = DisplayState.get(:weather, {:loc, name}, %{}) |> Map.put(:status, :error)
    DisplayState.put(:weather, {:loc, name}, existing)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Internal ────────────────────────────────────────────────────

  defp do_fetch_all(state) do
    # Spawn a worker that walks the location list one at a time and
    # mails each result back to us. Sequential fetching keeps only a
    # single TCP socket open at a time, which matters on the ESP32-C3.
    owner = self()

    pid =
      spawn(fn ->
        for loc <- state.locations do
          result = Client.fetch(%{lat: loc.lat, lon: loc.lon, units: state.units})
          send(owner, {:fetched, loc.name, result})
        end
      end)

    Log.debugf("Weather", "spawned fetch pid=~p locs=~p", [pid, length(state.locations)])

    state1 = cancel_timer(state)
    timer_ref = Process.send_after(self(), :fetch_all, state1.interval + jitter())
    %{state1 | fetch_timer: timer_ref}
  end

  defp jitter do
    # AtomVM provides :atomvm.random/0 (32-bit unsigned integer).
    # Scale it to 0–10% of the interval.
    max_jitter = div(@fetch_interval_ms, 10)
    rem(:atomvm.random(), max_jitter)
  end

  defp cancel_timer(state) do
    if state.fetch_timer do
      Process.cancel_timer(state.fetch_timer)
    end

    %{state | fetch_timer: nil}
  end
end
