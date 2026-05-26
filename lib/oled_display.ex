defmodule OledDisplay do
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

  @i2c_sda 3
  @i2c_scl 4

  @display_width 128
  @display_height 64

  def start() do
    i2c = open_i2c()
    display = open_display(i2c)

    show_splash(display)
    show_counter(display)
  end

  defp open_i2c() do
    opts = [
      sda: @i2c_sda,
      scl: @i2c_scl,
      clock_speed_hz: 400_000
    ]
    I2C.open(opts)
  end

  defp open_display(i2c_host) do
    opts = [
      i2c_host: i2c_host,
      compatible: "solomon-systech,ssd1306",
      width: @display_width,
      height: @display_height,
      invert: false
    ]
    AVMPort.open({:spawn, "display"}, opts)
  end

  defp update(display, items) do
    AVMPort.call(display, {:update, items})
  end

  defp show_splash(display) do
    items = [
      {:text, 16, 8, :default16px, 0xFFFFFF, 0x000000, "AtomVM"},
      {:text, 8, 32, :default16px, 0xFFFFFF, 0x000000, "ESP32-C3"},
      {:text, 8, 48, :default16px, 0xAAAAAA, 0x000000, "Elixir + JIT"},
      {:rect, 0, 0, @display_width, @display_height, 0x000000}
    ]
    update(display, items)
    Process.sleep(1500)
  end

  defp show_counter(display) do
    spawn(fn -> count_loop(display, 0) end)

    receive do
      :stop -> :ok
    end
  end

  defp count_loop(display, n) do
    text = Integer.to_string(n)
    items = [
      {:text, 8, 16, :default16px, 0xFFFFFF, 0x000000, "Counter:"},
      {:text, 24, 36, :default16px, 0x00FF00, 0x000000, text},
      {:rect, 0, 0, @display_width, @display_height, 0x000000}
    ]
    update(display, items)
    Process.sleep(1000)
    count_loop(display, n + 1)
  end
end
