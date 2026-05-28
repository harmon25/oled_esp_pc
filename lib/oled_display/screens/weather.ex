defmodule OledDisplay.Screens.Weather do
  @compile {:no_warn_undefined, [:avm_pubsub]}

  @moduledoc """
  Skeleton / spec for a weather screen.

  Not yet wired into the active flow. When the device is network-
  connected, this screen can be switched to via:

      :avm_pubsub.pub(:pubsub, :screen_request,
        {:switch, OledDisplay.Screens.Weather, location: "NYC"})

  Layout reuses the old "Weather Focus" style: centered icon +
  condition label, with temperature and humidity below.
  """

  @behaviour OledDisplay.Screen

  alias OledDisplay.IconData

  @bg 0x000000
  @fg 0xFFFFFF

  @refresh_ms 30_000

  # ── Screen behaviour ───────────────────────────────────────────

  @impl true
  def init(args) do
    state = %{
      location: Keyword.get(args, :location, "Unknown"),
      temp_c: Keyword.get(args, :temp_c, nil),
      humidity: Keyword.get(args, :humidity, nil),
      condition: Keyword.get(args, :condition, :unknown),
      icon: Keyword.get(args, :icon, :sun),
      last_updated: nil
    }

    {state, @refresh_ms}
  end

  @impl true
  def render(state) do
    weather = IconData.get(state.icon)
    label = IconData.weather_label(state.icon)

    temp_str = if state.temp_c, do: "#{state.temp_c}°C", else: "--°C"
    hum_str = if state.humidity, do: "#{state.humidity}%", else: "--%"

    items = [
      # Centered weather icon + label
      {:text, 56, 22, :default16px, @fg, :transparent, label},
      {:image, 56, 4, @bg, weather},
      # Bottom row: temp / humidity
      {:text, 84, 42, :default16px, @fg, :transparent, hum_str},
      {:image, 66, 42, :transparent, IconData.get(:humidity)},
      {:text, 20, 42, :default16px, @fg, :transparent, temp_str},
      {:image, 2, 42, :transparent, IconData.get(:temperature)},
      # Background
      {:rect, 0, 0, 128, 64, @bg}
    ]

    items
  end

  @impl true
  def handle_info(:tick, state) do
    # Future: trigger a background weather fetch here.
    {:noreply, state}
  end

  def handle_info({:weather_data, data}, state) do
    new_state = %{
      state
      | temp_c: data[:temp_c],
        humidity: data[:humidity],
        condition: data[:condition],
        icon: data[:icon] || :sun,
        last_updated: System.monotonic_time(:second)
    }

    {:noreply, new_state, [{:push, render(new_state)}]}
  end

  def handle_info({:wifi_status, _status}, state) do
    # Future: react to connection changes (e.g. disconnect → back to stats)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
