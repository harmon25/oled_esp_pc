# OledDisplay — AtomVM + SSD1306 on ESP32-C3

Elixir AtomVM application that drives an SSD1306 OLED display via I2C on ESP32-C3, using the `atomgl` port driver.

## Wiring

```
ESP32-C3 GPIO    SSD1306
─────────────────────────
GPIO 3  ──────── SDA
GPIO 4  ──────── SCL
3.3V    ──────── VCC
GND     ──────── GND
```

## Prerequisites

- **ESP-IDF v5.5.3** (installed to `~/.espressif`)
- **AtomVM** source at `~/Dev/AtomVM` (this project is designed to run on the firmware built from that tree)
- **Erlang/OTP 28** + **Elixir 1.19**

## Firmware Build (one-time)

The ESP32-C3 was flashed with AtomVM firmware featuring Elixir support, JIT, and the atomgl port driver:

```bash
# Source ESP-IDF
. ~/.espressif/v5.5.3/esp-idf/export.sh

# Build host tools and boot libraries
cd ~/Dev/AtomVM
mkdir -p build && cd build
cmake .. && make -j$(nproc)

# Build ESP32-C3 firmware with Elixir support
cd ~/Dev/AtomVM/src/platforms/esp32
idf.py -DATOMVM_ELIXIR_SUPPORT=on set-target esp32c3

# Enable JIT (set CONFIG_JIT_ENABLED=y in sdkconfig)
idf.py menuconfig   # AtomVM configuration → Enable just in time compilation

# Build and flash
idf.py build
idf.py -p /dev/ttyACM0 flash
```

The console was configured for USB Serial/JTAG (not the physical UART pins), so the same `/dev/ttyACM0` port is used for both flashing and serial output.

## Build & Flash the App

```bash
# Source ESP-IDF (required for esptool.py)
. ~/.espressif/v5.5.3/esp-idf/export.sh

# Fetch ExAtomVM dependency (one-time)
mix deps.get

# Compile and pack into .avm
mix atomvm.packbeam

# Flash to the main.avm partition (0x250000)
mix atomvm.esp32.flash --port /dev/ttyACM0 --baud 460800
```

## View Serial Output

```bash
# Requires a TTY (run in a real terminal):
idf.py -p /dev/ttyACM0 monitor

# Or using picocom:
picocom /dev/ttyACM0 -b 115200
```

## Screens

The app boots with a splash screen, then auto-rotates through available screens every 10 seconds. A short button press immediately cycles to the next screen.

| Screen | Description |
|--------|-------------|
| **Splash** | Boot phase: app name, WiFi status, weather fetch progress |
| **System Stats** | WiFi/IP, uptime, free heap, process count |
| **Weather** | Live wttr.in data; cycles locations every 5 s; skipped when offline |

## Font System

Custom fonts are stored as `.uff` binaries in `assets/fonts/` and auto-registered at compile time.

| Atom | File | Source | Size | Best for |
|------|------|--------|------|----------|
| `:small` | `spleen_6x12.uff` | Spleen (BSD-2-Clause) | 6×12 | Dense body text, 21 chars/line |
| `:medium` | `spleen_8x16.uff` | Spleen (BSD-2-Clause) | 8×16 | Labels, status lines, 16 chars/line |
| `:large` | `spleen_12x24.uff` | Spleen (BSD-2-Clause) | 12×24 | Headlines, large numbers, 10 chars/line |

All three fonts cover ASCII (U+0020–007E) plus the degree sign (U+00B0). Regenerate with:

```bash
python3 tools/gen_font.py /path/to/spleen-6x12.bdf  0 assets/fonts/spleen_6x12.uff
python3 tools/gen_font.py /path/to/spleen-8x16.bdf  0 assets/fonts/spleen_8x16.uff
python3 tools/gen_font.py /path/to/spleen-12x24.bdf 0 assets/fonts/spleen_12x24.uff numeric
```

BDF sources: https://github.com/fcambus/spleen

## Project Structure

```
oled_display/
├── README.md
├── AGENTS.md                           # Agent / developer instructions
├── mix.exs                             # Mix project (ExAtomVM config)
├── config/config.exs                   # WiFi credentials, weather locations/units
├── assets/
│   ├── fonts/                          # .uff font binaries (compile-time embedded)
│   └── icons/                          # .rgba icon binaries (compile-time embedded)
├── tools/
│   ├── gen_font.py                     # BDF/TTF → .uff converter
│   ├── gen_icons.py                    # XBM → .rgba converter
│   └── geocode.sh                      # Look up lat/lon for weather locations
└── lib/
    ├── oled_display.ex                 # App entrypoint (exports start/0)
    └── oled_display/
        ├── application_supervisor.ex   # OTP supervision tree
        ├── display.ex                  # GenServer: AtomGL port, tick, screen routing
        ├── display_state.ex            # ETS-backed shared state
        ├── fonts.ex                    # Compile-time font registry
        ├── icon_data.ex                # Compile-time RGBA8888 icon bitmaps
        ├── icons.ex                    # Inline text symbols (degree sign, etc.)
        ├── layouts.ex                  # Legacy layout helpers (retained for reuse)
        ├── wifi.ex                     # WiFi GenServer
        ├── weather.ex                  # Weather fetch GenServer (wttr.in)
        ├── weather/client.ex           # Raw gen_tcp HTTP/1.1 client
        └── screens/
            ├── splash.ex               # Boot splash renderer (not a Screen)
            ├── system_stats.ex         # System stats screen
            └── weather.ex              # Live weather screen
```

## Adding a New Icon

1. Add the 16×16 XBM byte array to `XBM_DATA` in `tools/gen_icons.py`
2. Run `python3 tools/gen_icons.py` — writes `assets/icons/<name>.rgba`
3. Add `@<name> File.read!(Path.join(@icons_dir, "<name>.rgba"))` in `icon_data.ex`
4. Add a `get(:<name>)` clause returning `{:rgba8888, 16, 16, @<name>}`
5. For hollow outline icons: `{:image, x, y, 0x000000, IconData.get(:<name>)}` (black bg)
6. For solid utility icons: `{:image, x, y, :transparent, IconData.get(:<name>)}`

## Adding a Weather Location

```bash
# Look up lat/lon
tools/geocode.sh "City Name"
```

Then add to `config/config.exs`:

```elixir
config :oled_display, :weather,
  locations: [
    %{name: "Toronto", lat: 43.6532, lon: -79.3832}
  ]
```

## Iterating

1. Edit files in `lib/oled_display/`
2. `mix atomvm.packbeam && mix atomvm.esp32.flash --port /dev/ttyACM0`
3. The board resets automatically after flashing

## Credits

- Weather icons from [Dhole/weather-pixel-icons](https://github.com/Dhole/weather-pixel-icons) — CC BY-SA 4.0
- Utility icons from [osar/arduino-oled-icons](https://github.com/osar/arduino-oled-icons) — GPL v3 (Artur Funk)
- Spleen fonts by Frederic Cambus — BSD 2-Clause
