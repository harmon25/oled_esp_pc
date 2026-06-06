import Config

# Set to true to enable [Tag] log lines on the serial monitor.
# false compiles all Log.debug/debugf calls away entirely (zero runtime cost).
config :oled_display, :log_enabled, true

config :oled_display,
  display: [
    i2c_sda: 3,
    i2c_scl: 4,
    width: 128,
    height: 64
  ],
  pubsub: :pubsub

config :oled_display, :weather,
  units: :celsius,
  fetch_interval_ms: 900_000,
  locations: [
    %{name: "Toronto", lat: 43.6532, lon: -79.3832},
    %{name: "Tokyo", lat: 35.6762, lon: 139.6503}
  ]
