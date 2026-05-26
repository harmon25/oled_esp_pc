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

  def start() do
    OledDisplay.ApplicationSupervisor.start_link()
    Process.sleep(:infinity)
  end
end
