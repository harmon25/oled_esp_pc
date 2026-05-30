defmodule OledDisplay.Layouts do
  alias OledDisplay.IconData

  @bg 0x000000
  @fg 0xFFFFFF
  @dim 0xAAAAAA

  @doc """
  Build the full display-item list for a given layout.
  Items are returned in draw order (first = topmost, last = background). The
  caller is responsible for appending the full-screen rect as the last item.
  """
  def build(layout, weather_key, temp_str, humidity_str, time_str, wifi_label) do
    items =
      case layout do
        :a -> layout_a(weather_key, temp_str, humidity_str, time_str, wifi_label)
        :b -> layout_b(weather_key, temp_str, humidity_str, time_str, wifi_label)
        :c -> layout_c(weather_key, temp_str, humidity_str, time_str, wifi_label)
      end

    items ++ [{:rect, 0, 0, 128, 64, @bg}]
  end

  # ── Layout A: Full Dashboard ────────────────────────────────────
  #
  # [WiFi] connected          [Clock] 01:23
  # [Sun]  Sunny
  # [Temp] 24°C    [Humidity] 60%

  defp layout_a(weather_key, temp_str, humidity_str, time_str, wifi_label) do
    weather = IconData.get(weather_key)
    weather_icon = {:image, 2, 22, @bg, weather}

    weather_text =
      {:text, 20, 22, :default16px, @fg, :transparent, IconData.weather_label(weather_key)}

    temp = IconData.get(:temperature)
    temp_icon = {:image, 2, 42, :transparent, temp}
    temp_text = {:text, 20, 42, :default16px, @fg, :transparent, temp_str}

    hum = IconData.get(:humidity)
    hum_icon = {:image, 66, 42, :transparent, hum}
    hum_text = {:text, 84, 42, :default16px, @fg, :transparent, humidity_str}

    wifi = IconData.get(:wifi1)
    wifi_icon = {:image, 2, 2, :transparent, wifi}
    wifi_text = {:text, 20, 2, :default16px, @dim, :transparent, wifi_label}

    clk = IconData.get(:clock)
    clk_icon = {:image, 74, 2, :transparent, clk}
    clk_text = {:text, 92, 2, :default16px, @fg, :transparent, time_str}

    [
      clk_text,
      clk_icon,
      wifi_text,
      wifi_icon,
      hum_text,
      hum_icon,
      temp_text,
      temp_icon,
      weather_text,
      weather_icon
    ]
  end

  # ── Layout B: Weather Focus ─────────────────────────────────────
  #
  #         [Sun]     ← centered
  #         Sunny
  # [Temp] 24°C    [Humidity] 60%

  defp layout_b(weather_key, temp_str, humidity_str, _time_str, _wifi_label) do
    weather = IconData.get(weather_key)
    weather_icon = {:image, 56, 4, @bg, weather}

    weather_text =
      {:text, 56, 22, :default16px, @fg, :transparent, IconData.weather_label(weather_key)}

    temp = IconData.get(:temperature)
    temp_icon = {:image, 2, 42, :transparent, temp}
    temp_text = {:text, 20, 42, :default16px, @fg, :transparent, temp_str}

    hum = IconData.get(:humidity)
    hum_icon = {:image, 66, 42, :transparent, hum}
    hum_text = {:text, 84, 42, :default16px, @fg, :transparent, humidity_str}

    [hum_text, hum_icon, temp_text, temp_icon, weather_text, weather_icon]
  end

  # ── Layout C: Compact Stack ─────────────────────────────────────
  #
  # [Clock] 01:23
  # [Temp] 24°C    [Humidity] 60%
  # [WiFi] connected
  # [Sun]  Sunny

  defp layout_c(weather_key, temp_str, humidity_str, time_str, wifi_label) do
    weather = IconData.get(weather_key)
    weather_icon = {:image, 2, 56, @bg, weather}

    weather_text =
      {:text, 20, 56, :default16px, @fg, :transparent, IconData.weather_label(weather_key)}

    temp = IconData.get(:temperature)
    temp_icon = {:image, 2, 20, :transparent, temp}
    temp_text = {:text, 20, 20, :default16px, @fg, :transparent, temp_str}

    hum = IconData.get(:humidity)
    hum_icon = {:image, 66, 20, :transparent, hum}
    hum_text = {:text, 84, 20, :default16px, @fg, :transparent, humidity_str}

    wifi = IconData.get(:wifi1)
    wifi_icon = {:image, 2, 38, :transparent, wifi}
    wifi_text = {:text, 20, 38, :default16px, @dim, :transparent, wifi_label}

    clk = IconData.get(:clock)
    clk_icon = {:image, 2, 2, :transparent, clk}
    clk_text = {:text, 20, 2, :default16px, @fg, :transparent, time_str}

    [
      weather_text,
      weather_icon,
      wifi_text,
      wifi_icon,
      hum_text,
      hum_icon,
      temp_text,
      temp_icon,
      clk_text,
      clk_icon
    ]
  end
end
