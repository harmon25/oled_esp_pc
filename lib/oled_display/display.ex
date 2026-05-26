defmodule OledDisplay.Display do
  @i2c_sda 3
  @i2c_scl 4
  @display_width 128
  @display_height 64

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

  def handle_info({:wifi_status, status}, state) do
    {:noreply, %{state | wifi_status: status},
     [{:push, display_items(%{state | wifi_status: status})}]}
  end

  def handle_info(:tick, state) do
    schedule_tick()
    new_state = %{state | counter: state.counter + 1}
    {:noreply, new_state, [{:push, display_items(new_state)}]}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, 1000)
  end

  defp display_items(state) do
    [
      {:text, 8, 4, :default16px, 0xFFFFFF, 0x000000, "Counter:"},
      {:text, 24, 24, :default16px, 0x00FF00, 0x000000, Integer.to_string(state.counter)},
      {:text, 8, 48, :default16px, 0xAAAAAA, 0x000000, wifi_label(state.wifi_status)},
      {:rect, 0, 0, @display_width, @display_height, 0x000000}
    ]
  end

  defp wifi_label(:initializing), do: "WiFi: init"
  defp wifi_label(:connecting), do: "WiFi: connecting..."
  defp wifi_label(:ap_mode), do: "WiFi: AP Mode"
  defp wifi_label(:connected), do: "WiFi: connected"
  defp wifi_label(_), do: "WiFi: ?"

  defp splash_items do
    [
      {:text, 16, 8, :default16px, 0xFFFFFF, 0x000000, "AtomVM"},
      {:text, 8, 32, :default16px, 0xFFFFFF, 0x000000, "ESP32-C3"},
      {:text, 8, 48, :default16px, 0xAAAAAA, 0x000000, "Elixir + JIT"},
      {:rect, 0, 0, @display_width, @display_height, 0x000000}
    ]
  end
end
