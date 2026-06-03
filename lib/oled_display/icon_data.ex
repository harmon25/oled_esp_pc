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
  @icons_dir Path.expand("../../assets/icons", __DIR__)

  # Each attribute is the complete ready-to-use tuple.  Collapsing the binary
  # read and the tuple construction into a single attribute ensures the binary
  # lives only once in the module's literal pool — no separate raw-binary entry
  # that AtomVM might allocate independently alongside the tuple.
  @sun {:rgba8888, 16, 16, File.read!(Path.join(@icons_dir, "weather_sun.rgba"))}
  @cloud {:rgba8888, 16, 16, File.read!(Path.join(@icons_dir, "weather_cloud.rgba"))}
  @cloud_sun {:rgba8888, 16, 16, File.read!(Path.join(@icons_dir, "weather_cloud_sun.rgba"))}
  @rain1 {:rgba8888, 16, 16, File.read!(Path.join(@icons_dir, "weather_rain1.rgba"))}
  @lightning {:rgba8888, 16, 16, File.read!(Path.join(@icons_dir, "weather_lightning.rgba"))}
  @snow {:rgba8888, 16, 16, File.read!(Path.join(@icons_dir, "weather_snow.rgba"))}
  @wind {:rgba8888, 16, 16, File.read!(Path.join(@icons_dir, "weather_wind.rgba"))}
  @moon {:rgba8888, 16, 16, File.read!(Path.join(@icons_dir, "weather_moon.rgba"))}
  @rain2 {:rgba8888, 16, 16, File.read!(Path.join(@icons_dir, "weather_rain2.rgba"))}
  @rain_lightning {:rgba8888, 16, 16, File.read!(Path.join(@icons_dir, "weather_rain_lightning.rgba"))}
  @wifi1 {:rgba8888, 16, 16, File.read!(Path.join(@icons_dir, "utility_wifi1.rgba"))}
  @wifi_off {:rgba8888, 16, 16, File.read!(Path.join(@icons_dir, "utility_wifi_off.rgba"))}
  @up_arrow {:rgba8888, 16, 16, File.read!(Path.join(@icons_dir, "utility_up_arrow.rgba"))}
  @temperature {:rgba8888, 16, 16, File.read!(Path.join(@icons_dir, "utility_temperature.rgba"))}
  @humidity {:rgba8888, 16, 16, File.read!(Path.join(@icons_dir, "utility_humidity.rgba"))}
  @clock {:rgba8888, 16, 16, File.read!(Path.join(@icons_dir, "utility_clock.rgba"))}

  def get(:sun), do: @sun
  def get(:cloud), do: @cloud
  def get(:cloud_sun), do: @cloud_sun
  def get(:rain1), do: @rain1
  def get(:lightning), do: @lightning
  def get(:snow), do: @snow
  def get(:wind), do: @wind
  def get(:moon), do: @moon
  def get(:rain2), do: @rain2
  def get(:rain_lightning), do: @rain_lightning
  def get(:wifi1), do: @wifi1
  def get(:wifi_off), do: @wifi_off
  def get(:up_arrow), do: @up_arrow
  def get(:temperature), do: @temperature
  def get(:humidity), do: @humidity
  def get(:clock), do: @clock

  def weather_icons,
    do: [
      :sun,
      :cloud_sun,
      :cloud,
      :rain1,
      :rain2,
      :rain_lightning,
      :lightning,
      :snow,
      :wind,
      :moon
    ]

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
