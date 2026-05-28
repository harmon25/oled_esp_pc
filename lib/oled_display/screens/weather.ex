defmodule OledDisplay.Screens.Weather do
  @compile {:no_warn_undefined, [:avm_pubsub]}

  @moduledoc """
  Weather screen with a cycling demo mode.

  Cycles through all 10 weather conditions every 3 seconds so the
  icons and layout can be verified on the hardware without a network
  connection.

  When the device is network-connected, switch to this screen and push
  real data via pubsub:

      :avm_pubsub.pub(:pubsub, [:screen_request],
        {:switch, OledDisplay.Screens.Weather, location: "NYC"})

      # Then push live data:
      :avm_pubsub.pub(:pubsub, [:weather_data],
        %{temp_c: 18, humidity: 72, icon: :cloud_sun})

  Layout (128×64):
    y= 2  [16×16 icon]  Condition label   (cozette 6×13)
    y=20  [16×16 icon]  City / location   (cozette 6×13)
    y=38  [temp icon]  22°C   [hum icon]  65%
    y=52  ← Demo cycling indicator (spleen 5×8)
  """

  @behaviour OledDisplay.Screen

  alias OledDisplay.IconData

  @bg 0x000000
  @fg 0xFFFFFF

  # CP437 degree sign (0xF8) for use with :default16px
  @deg <<0xF8>>

  @demo_tick_ms 3_000

  # Cycling demo scenarios: {icon, temp_c, humidity}
  @demo_scenarios [
    {:sun,           22, 45},
    {:cloud_sun,     18, 58},
    {:cloud,         14, 72},
    {:rain1,         11, 85},
    {:rain2,          9, 91},
    {:rain_lightning,  8, 94},
    {:lightning,      7, 89},
    {:snow,          -2, 78},
    {:wind,          10, 55},
    {:moon,          16, 50}
  ]

  # ── Screen behaviour ───────────────────────────────────────────

  @impl true
  def init(args) do
    demo_index = 0
    {icon, temp_c, humidity} = Enum.at(@demo_scenarios, demo_index)

    state = %{
      location:    Keyword.get(args, :location, "Demo Mode"),
      temp_c:      Keyword.get(args, :temp_c, temp_c),
      humidity:    Keyword.get(args, :humidity, humidity),
      icon:        Keyword.get(args, :icon, icon),
      demo_index:  demo_index,
      demo_total:  length(@demo_scenarios)
    }

    {state, @demo_tick_ms}
  end

  @impl true
  def render(state) do
    weather_icon = IconData.get(state.icon)
    label        = IconData.weather_label(state.icon)
    temp_str     = "#{state.temp_c}#{@deg}C"
    hum_str      = "#{state.humidity}%"
    demo_str     = "#{state.demo_index + 1}/#{state.demo_total}"

    [
      # Row 0: weather icon + condition label
      {:image,  2,  2, @bg, weather_icon},
      {:text,  22,  4, :cozette, @fg, :transparent, label},

      # Row 1: location
      {:text,  22, 20, :cozette, @fg, :transparent, state.location},

      # Row 2: temperature + humidity with utility icons
      {:image,  2, 38, :transparent, IconData.get(:temperature)},
      {:text,  20, 40, :default16px, @fg, :transparent, temp_str},
      {:image, 68, 38, :transparent, IconData.get(:humidity)},
      {:text,  86, 40, :default16px, @fg, :transparent, hum_str},

      # Row 3: small demo cycle counter (bottom-right)
      {:text, 96, 54, :spleen5x8, @fg, :transparent, demo_str},

      # Background (rendered last = drawn first by AtomGL)
      {:rect, 0, 0, 128, 64, @bg}
    ]
  end

  @impl true
  def handle_info(:tick, state) do
    # Advance to next demo scenario
    next_index = rem(state.demo_index + 1, state.demo_total)
    {icon, temp_c, humidity} = Enum.at(@demo_scenarios, next_index)

    new_state = %{state | demo_index: next_index, icon: icon, temp_c: temp_c, humidity: humidity}
    {:noreply, new_state, [{:push, render(new_state)}]}
  end

  def handle_info({:weather_data, data}, state) do
    # Accept live data from a future network fetch; stop demo cycling
    new_state = %{
      state
      | temp_c:   data[:temp_c]   || state.temp_c,
        humidity: data[:humidity] || state.humidity,
        icon:     data[:icon]     || state.icon
    }

    {:noreply, new_state, [{:push, render(new_state)}]}
  end

  def handle_info({:wifi_status, _status}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
