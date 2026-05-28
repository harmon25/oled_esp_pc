defmodule OledDisplay.Display do
  alias OledDisplay.IconData

  @i2c_sda 3
  @i2c_scl 4
  @display_width 128
  @display_height 64

  # ── Demo data pools ──────────────────────────────────────────────

  @weather_icons IconData.weather_icons()
  @deg <<0xF8>>  # CP437 degree sign (font uses CP437, not Latin-1)
  @temperatures ["18#{@deg}C", "22#{@deg}C", "26#{@deg}C", "30#{@deg}C", "34#{@deg}C", "38#{@deg}C", "42#{@deg}C"]
  @humidities ["40%", "55%", "70%", "85%", "95%"]
  @layouts [:a, :b, :c]

  # ── Lifecycle ────────────────────────────────────────────────────

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def start_link(opts) do
    i2c = I2C.open(sda: @i2c_sda, scl: @i2c_scl, clock_speed_hz: 400_000)

    display =
      AVMPort.open({:spawn, "display"},
        i2c_host: i2c,
        compatible: "solomon-systech,ssd1306",
        width: @display_width,
        height: @display_height,
        invert: false
      )

    AVMPort.call(display, {:update, splash_items()})
    Process.sleep(1500)

    :avm_scene.start_link(__MODULE__, opts, display_server: {:port, display})
  end

  def init(_opts) do
    :avm_pubsub.sub(:pubsub, :wifi_status, self())

    wifi_status = GenServer.call(OledDisplay.WiFi, :get_status)

    schedule_tick()

    {:ok, %{wifi_status: wifi_status, counter: 0}}
  end

  # ── Event handlers ───────────────────────────────────────────────

  def handle_info({:wifi_status, status}, state) do
    new_state = %{state | wifi_status: status}
    {:noreply, new_state, [{:push, display_items(new_state)}]}
  end

  def handle_info(:tick, state) do
    schedule_tick()
    new_state = %{state | counter: state.counter + 1}
    {:noreply, new_state, [{:push, display_items(new_state)}]}
  end

  # ── Display list construction ────────────────────────────────────

  defp display_items(state) do
    weather_key = Enum.at(@weather_icons, div(state.counter, 3) |> rem(length(@weather_icons)))
    temp_str = Enum.at(@temperatures, div(state.counter, 5) |> rem(length(@temperatures)))
    humidity_str = Enum.at(@humidities, div(state.counter, 5) |> rem(length(@humidities)))
    layout = Enum.at(@layouts, div(state.counter, 8) |> rem(length(@layouts)))
    time_str = format_time(state.counter)
    wifi = wifi_label(state.wifi_status)

    OledDisplay.Layouts.build(layout, weather_key, temp_str, humidity_str, time_str, wifi)
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp format_time(seconds) do
    h = div(seconds, 3600) |> Kernel.rem(24)
    m = div(seconds, 60) |> Kernel.rem(60)
    s = rem(seconds, 60)
    pad = fn n -> if n < 10, do: "0#{n}", else: Integer.to_string(n) end
    "#{pad.(h)}:#{pad.(m)}:#{pad.(s)}"
  end

  defp wifi_label(:initializing), do: "init.."
  defp wifi_label(:connecting), do: "connecting"
  defp wifi_label(:ap_mode), do: "AP Mode"
  defp wifi_label(:connected), do: "connected"
  defp wifi_label(_), do: "?"

  defp schedule_tick do
    Process.send_after(self(), :tick, 1000)
  end

  defp splash_items do
    [
      {:text, 16, 8, :default16px, 0xFFFFFF, 0x000000, "AtomVM"},
      {:text, 8, 32, :default16px, 0xFFFFFF, 0x000000, "ESP32-C3"},
      {:text, 8, 48, :default16px, 0xAAAAAA, 0x000000, "Elixir + JIT"},
      {:rect, 0, 0, @display_width, @display_height, 0x000000}
    ]
  end
end
