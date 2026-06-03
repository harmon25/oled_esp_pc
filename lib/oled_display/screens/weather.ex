defmodule OledDisplay.Screens.Weather do
  @moduledoc """
  Weather screen showing real data fetched from Open-Meteo.

  Cycles through configured locations every 5 seconds.
  Data is read from the shared ETS cache maintained by
  OledDisplay.Weather.
  """

  @behaviour OledDisplay.Screen

  alias OledDisplay.DisplayState
  alias OledDisplay.IconData

  @bg 0x000000
  @fg 0xFFFFFF
  @deg <<0xF8>>

  # How long each location stays on screen before cycling to the next
  @cycle_ms 5_000
  # Cached data older than this is marked with a "*" in the counter
  @stale_threshold_ms 30 * 60 * 1000

  # ── Screen behaviour ───────────────────────────────────────────

  @impl true
  def available?(_args) do
    {connected, _, _} = OledDisplay.WiFi.status()
    connected and length(locations()) > 0
  end

  @impl true
  def init(_args) do
    locs = locations()
    units = DisplayState.get(:weather, :units, :celsius)

    state = %{
      locations: locs,
      index: 0,
      units: units
    }

    {state, @cycle_ms}
  end

  @impl true
  def render(state) do
    current = Enum.at(state.locations, state.index)
    data = DisplayState.get(:weather, {:loc, current.name}, %{})

    {icon, label, temp_str, hum_str, counter} = format(data, state)

    [
      # Row 0: weather icon + condition label
      {:image, 2, 2, @bg, icon},
      {:text, 22, 4, :spleen5x8, @fg, :transparent, label},

      # Row 1: location name
      {:text, 22, 20, :spleen5x8, @fg, :transparent, current.name},

      # Row 2: temperature + humidity with utility icons
      {:image, 2, 38, :transparent, IconData.get(:temperature)},
      {:text, 20, 40, :default16px, @fg, :transparent, temp_str},
      {:image, 68, 38, :transparent, IconData.get(:humidity)},
      {:text, 86, 40, :default16px, @fg, :transparent, hum_str},

      # Row 3: location counter (bottom-right)
      {:text, 96, 54, :spleen5x8, @fg, :transparent, counter},

      # Background
      {:rect, 0, 0, 128, 64, @bg}
    ]
  end

  @impl true
  def handle_info(:tick, state) do
    next_index = rem(state.index + 1, length(state.locations))
    new_state = %{state | index: next_index}
    {:noreply, new_state, [{:push, render(new_state)}]}
  end

  def handle_info({:weather_data, _name}, state) do
    {:noreply, state, [{:push, render(state)}]}
  end

  def handle_info({:wifi_status, _status}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp locations do
    DisplayState.get(:weather, :locations, [])
  end

  # Translates an ETS weather entry into the tuple consumed by render/1.
  # Falls back to a "Loading"/"Error" placeholder when no fresh data exists.
  defp format(data, state) do
    base_counter = "#{state.index + 1}/#{length(state.locations)}"

    case Map.get(data, :status, :pending) do
      :ok ->
        counter = if stale?(data), do: base_counter <> "*", else: base_counter

        {
          IconData.get(data.icon),
          IconData.weather_label(data.icon),
          format_temp(data.temp, state.units),
          "#{data.humidity}%",
          counter
        }

      status ->
        label = if status == :error, do: "Error", else: "Loading"
        {IconData.get(:cloud), label, "--#{@deg}C", "--%", base_counter}
    end
  end

  defp format_temp(temp, :fahrenheit) do
    "#{round(temp)}#{@deg}F"
  end

  defp format_temp(temp, _) do
    "#{round(temp)}#{@deg}C"
  end

  defp stale?(data) do
    now = :erlang.system_time(:millisecond)
    now - Map.get(data, :fetched_at, 0) > @stale_threshold_ms
  end
end
