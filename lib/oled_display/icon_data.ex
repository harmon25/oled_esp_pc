defmodule OledDisplay.Xbm do
  import Bitwise

  def to_rgba(xbm, width, height) do
    bpr = div(width + 7, 8)
    for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
      byte = :binary.at(xbm, y * bpr + div(x, 8))
      mask = 1 <<< rem(x, 8)
      if (byte &&& mask) != 0 do
        <<0xFF, 0xFF, 0xFF, 0xFF>>
      else
        <<0x00, 0x00, 0x00, 0x00>>
      end
    end
  end
end

defmodule OledDisplay.IconData do
  @icons_dir Path.expand("../../priv/icons", __DIR__)

  @sun     File.read!(Path.join(@icons_dir, "weather_sun.rgba"))
  @cloud   File.read!(Path.join(@icons_dir, "weather_cloud.rgba"))
  @cloud_sun File.read!(Path.join(@icons_dir, "weather_cloud_sun.rgba"))
  @rain1   File.read!(Path.join(@icons_dir, "weather_rain1.rgba"))
  @lightning File.read!(Path.join(@icons_dir, "weather_lightning.rgba"))
  @snow    File.read!(Path.join(@icons_dir, "weather_snow.rgba"))
  @wind    File.read!(Path.join(@icons_dir, "weather_wind.rgba"))
  @moon    File.read!(Path.join(@icons_dir, "weather_moon.rgba"))
  @rain2   File.read!(Path.join(@icons_dir, "weather_rain2.rgba"))
  @rain_lightning File.read!(Path.join(@icons_dir, "weather_rain_lightning.rgba"))
  @wifi1   File.read!(Path.join(@icons_dir, "utility_wifi1.rgba"))
  @temperature File.read!(Path.join(@icons_dir, "utility_temperature.rgba"))
  @humidity File.read!(Path.join(@icons_dir, "utility_humidity.rgba"))
  @clock   File.read!(Path.join(@icons_dir, "utility_clock.rgba"))

  def get(:sun), do: {:rgba8888, 16, 16, @sun}
  def get(:cloud), do: {:rgba8888, 16, 16, @cloud}
  def get(:cloud_sun), do: {:rgba8888, 16, 16, @cloud_sun}
  def get(:rain1), do: {:rgba8888, 16, 16, @rain1}
  def get(:lightning), do: {:rgba8888, 16, 16, @lightning}
  def get(:snow), do: {:rgba8888, 16, 16, @snow}
  def get(:wind), do: {:rgba8888, 16, 16, @wind}
  def get(:moon), do: {:rgba8888, 16, 16, @moon}
  def get(:rain2), do: {:rgba8888, 16, 16, @rain2}
  def get(:rain_lightning), do: {:rgba8888, 16, 16, @rain_lightning}
  def get(:wifi1), do: {:rgba8888, 16, 16, @wifi1}
  def get(:temperature), do: {:rgba8888, 16, 16, @temperature}
  def get(:humidity), do: {:rgba8888, 16, 16, @humidity}
  def get(:clock), do: {:rgba8888, 16, 16, @clock}

  def weather_icons, do: [:sun, :cloud_sun, :cloud, :rain1, :rain2, :rain_lightning, :lightning, :snow, :wind, :moon]

  def weather_label(:sun), do: "Sunny"
  def weather_label(:cloud_sun), do: "P.Cloudy"
  def weather_label(:cloud), do: "Cloudy"
  def weather_label(:rain1), do: "Rain"
  def weather_label(:rain2), do: "Heavy Rain"
  def weather_label(:rain_lightning), do: "Thunder"
  def weather_label(:lightning), do: "Storm"
  def weather_label(:snow), do: "Snow"
  def weather_label(:wind), do: "Windy"
  def weather_label(:moon), do: "Clear Night"
end
