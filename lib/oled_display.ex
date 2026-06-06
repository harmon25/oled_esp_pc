defmodule OledDisplay do
  @compile {:no_warn_undefined, [I2C, AVMPort, :avm_pubsub]}

  @moduledoc """
  AtomVM SSD1306 OLED display demo for ESP32-C3.

  Wiring (ESP32-C3 GPIO → SSD1306):
    GPIO 3 → SDA
    GPIO 4 → SCL
    VCC    → 3.3V
    GND    → GND

  Requires AtomVM firmware built with `ATOMVM_ELIXIR_SUPPORT=on`
  and the `atomgl` port driver component.
  """
  @display_cfg Application.compile_env(:oled_display, :display, [])
  @weather_cfg Application.compile_env(:oled_display, :weather, [])

  def start() do
    IO.puts("Trying to boot...")
    :avm_pubsub.start(:pubsub)
    # Open hardware in the top-level entry process, which lives for the
    # entire device uptime. This ensures the I2C driver and display port
    # are allocated exactly once — supervised GenServer restarts no longer
    # touch hardware and therefore cannot trigger "i2c driver install error"
    # on the second start.
    i2c =
      I2C.open(sda: @display_cfg[:i2c_sda], scl: @display_cfg[:i2c_scl], clock_speed_hz: 400_000)

    display =
      AVMPort.open(
        {:spawn, "display"},
        i2c_host: i2c,
        compatible: "solomon-systech,ssd1306",
        width: @display_cfg[:width],
        height: @display_cfg[:height],
        invert: false
      )

    # Register custom fonts once — no need to repeat on Display restarts.
    for {name, bin} <- OledDisplay.Fonts.all() do
      AVMPort.call(display, {:register_font, name, bin})
    end

    OledDisplay.Display.wipe(display)


    # Show the boot splash immediately so the panel is never blank.
    # DisplayState is not up yet, so we compute locations_empty? directly
    # from compile-time config rather than ETS.
    locations_empty? = Keyword.get(@weather_cfg, :locations, []) == []

    initial_splash = %{
      tick_count: 0,
      boot_min_ticks: 10,
      wifi_status: nil,
      wifi_ip: nil,
      wifi_ap_ssid: nil,
      weather_ready?: false,
      locations_empty?: locations_empty?
    }

    AVMPort.call(display, {:update, OledDisplay.Screens.Splash.render(initial_splash)})

    OledDisplay.ApplicationSupervisor.start_link(display: display)
    Process.sleep(:infinity)
  end
end
