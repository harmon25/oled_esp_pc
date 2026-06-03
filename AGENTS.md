# OledDisplay — Agent instructions

Multi-module AtomVM app for SSD1306 OLED on ESP32-C3. No tests, no CI.

## App entrypoint

- `OledDisplay.start/0` — called by AtomVM on boot (configured in mix.exs `atomvm: [start: OledDisplay]`)
- `OledDisplay` is the only module packed into `main.avm`; all runtime deps (I2C, AVMPort, atomgl) live in the pre-flashed boot AVM partition

## Hardware

- I2C: GPIO 3 (SDA), GPIO 4 (SCL), 400 kHz
- Display: SSD1306, 128×64

## Module layout

- `lib/oled_display.ex` — app entrypoint (exports `start/0`)
- `lib/oled_display/screen.ex` — behaviour definition for display screens (`init/1`, `render/1`, `handle_info/2`, `available?/1`)
- `lib/oled_display/display.ex` — GenServer driving AtomGL via `avm_scene`; owns the hardware port, manages a `:boot` phase, then routes ticks and pubsub to the active screen; handles screen switching and auto-rotation
- `lib/oled_display/display_state.ex` — GenServer that owns the shared `:oled_display_state` ETS table; provides `get/3`, `put/3`, `delete/2`, `all/1`
- `lib/oled_display/screens/splash.ex` — **pure boot-phase renderer** (not a Screen). Driven by `Display` during boot to show app name, real WiFi status, weather fetch status, and an animated progress bar
- `lib/oled_display/screens/system_stats.ex` — shows WiFi status / AP name / IP, uptime, heap, and process count; counters persisted in ETS so uptime survives screen cycling
- `lib/oled_display/screens/weather.ex` — live Open-Meteo weather screen; cycles through configured locations every 5 s; skipped when offline or no locations configured
- `lib/oled_display/weather.ex` — GenServer that fetches weather from wttr.in over plain HTTP, caches results in ETS, and publishes on `:avm_pubsub`
- `lib/oled_display/weather/client.ex` — raw `:gen_tcp` HTTP/1.1 client for wttr.in's pipe-delimited format endpoint
- `lib/oled_display/icon_data.ex` — 16 pre-rendered 16×16 RGBA8888 icons read from `assets/icons/*.rgba` at compile time. `OledDisplay.Xbm` provides XBM→RGBA utility (also usable at runtime).
- `lib/oled_display/layouts.ex` — legacy layout helpers (A/B/C variants); retained for future Weather screen reuse
- `lib/oled_display/wifi.ex` — WiFi GenServer; mirrors status into `DisplayState`
- `lib/oled_display/application_supervisor.ex` — OTP supervision tree

## Screen architecture

Each screen implements the `OledDisplay.Screen` behaviour. `Display` owns the hardware port, subscribes to `:avm_pubsub` (`:wifi_status`, `:screen_request`, `:weather_ready`, `:weather_data`), and routes every `:tick` and pubsub message to the active screen.

**Screen switching API:** any process can request a switch via `:avm_pubsub`:
```elixir
:avm_pubsub.pub(:pubsub, :screen_request, {:switch, OledDisplay.Screens.Weather, []})
```

**Boot phase (`:boot` mode)**
`Display` starts in `:boot` mode. It drives `Splash.render/1` directly (Splash is **not** a `Screen`). Boot exits when:
- at least `boot_min_ms` (2000 ms) have elapsed, **and**
- WiFi is ready (`:connected` or `:ap_mode`), **and**
- at least one location has been fetched successfully (or no locations are configured), **or**
- `boot_timeout_ms` (10000 ms) is reached.

During `:boot`: screen requests and button short-presses are ignored. Button long-press (WiFi credential reset) stays active.

**Auto-rotation**
In `:running` mode, `Display` rotates through `@screens` every 10 s. Screens that return `false` from `available?/1` are skipped (e.g. `Weather` when offline). A short button press immediately cycles to the next available screen and resets the 10 s timer.

**Current flow:**
```
[Splash] —boot phase, 200 ms ticks—► [System Stats] —10 s auto-rotate—► [Weather] —10 s—► ...
```

## Icon system

All icons are 16×16 pixels, stored as RGBA8888 binaries (1024 bytes each). Weather icons from [Dhole/weather-pixel-icons](https://github.com/Dhole/weather-pixel-icons) (CC BY-SA 4.0). Utility icons (WiFi, WiFi-off, temp, humidity, clock, up-arrow) from [osar/arduino-oled-icons](https://github.com/osar/arduino-oled-icons) (GPL v3, Artur Funk), plus generated `wifi_off` and `up_arrow` overlays.

**Important:** Icons are embedded into the `.avm` at **compile time** via `File.read!` in `icon_data.ex`. Source files live in `assets/icons/` (not `priv/`, to avoid packing them twice). Attempting to read files at runtime with `:code.priv_dir/1`, `File.read!/1`, or the process dictionary (`Process.get/1`, `Process.put/2`) **will crash** on this AtomVM build — those modules are not available. Always embed binaries as module attributes.

The `OledDisplay.Xbm.to_rgba/3` converter expands XBM bit-packed data (X11 format, LSB-first, row-major) to RGBA8888 at compile time. Each 1-bit → `0xFFFFFFFF` (white opaque), 0-bit → `0x00000000` (transparent). The converter also works at runtime if needed.

**AtomGL font encoding:** The `:default16px` font is the Linux kernel `font_8x16` in **CP437** encoding (not Latin-1/UTF-8). Use raw byte values for extended characters — e.g. the degree sign is `<<0xF8>>` (CP437 `0xF8`), not `°` (UTF-8 `0xC2 0xB0`) or `<<0xB0>>` (Latin-1, which is a shade block in CP437). Define as a module attribute: `@deg <<0xF8>>`.

**Weather icon rendering (May 2026):** The Dhole icons are outlines with hollow interiors. On AtomGL's monochrome driver, transparent pixels in an image with a `:transparent` background cause the scanline renderer to stop, producing a "split in half" appearance. The fix is to keep the original hollow XBM outlines and set the image `BackgroundColor` to black (`0x000000`) in the display list. Transparent interior pixels then render as black, matching the screen background, and the outline draws correctly. The `assets/icons/*.rgba` files are direct XBM-to-RGBA conversions (no fill) generated by `tools/gen_icons.py`. Preview PNGs are written to `icon_previews/` at the project root.

## Font system

Custom fonts are stored as `.uff` binaries in `assets/fonts/` and auto-registered at compile time via `OledDisplay.Fonts`. The `:default16px` built-in (8×16 CP437) is always available; additional fonts must be registered before use.

**Registered fonts:**

| Atom | File | Source | Size | Best for |
|---|---|---|---|---|
| `:spleen5x8` | `spleen_5x8.uff` | Spleen (BSD-2) | 5×8 | Dense rows, up to 16×8 chars |
| `:cozette` | `cozette_6x13.uff` | Cozette (MIT) | 6×13 | Body text, 21×4 chars |
| `:pixop16` | `pixel_operator_16.uff` | Pixel Operator (CC0) | 8×16 | Headlines / large numbers |

All three are rendered with **hinted monochrome bitmaps** (`FT_LOAD_TARGET_MONO`) so thin strokes (e.g. `m`, `w`) stay crisp on a 1-bit OLED. No anti-aliased grayscale path is used.

**Auto-registration:**
`lib/oled_display/fonts.ex` scans `assets/fonts/*.uff` at compile time and returns a `[{atom, binary}, ...]` list from `OledDisplay.Fonts.all/0`. `display.ex` loops over this list and calls `{:register_font, atom, binary}` for each entry. Each `.uff` is declared as `@external_resource` so Mix recompiles when fonts change.

**Generating a new font:** `tools/gen_font.py` converts TTF/OTF/BDF/PCF to the ufontlib IFF (`.uff`) format using freetype-py. Targets printable ASCII (0x20–0x7E), uncompressed, 4bpp nibble layout.

```bash
python3 tools/gen_font.py <font_path> <size_px> assets/fonts/<name>.uff
```

- For BDF/PCF bitmap fonts the `size_px` argument is ignored (the strike is fixed).
- For TTF/OTF, the script uses `FT_LOAD_RENDER | FT_LOAD_MONOCHROME | FT_LOAD_TARGET_MONO` to emit crisp 1-bit glyphs. Sizes below ~12 px with the old anti-aliased path lost thin strokes; the mono path fixes this.

**Note:** `tools/` scripts are host-only. Never put them in `priv/` — that directory is bundled into the `.avm`.

## WiFi AP naming

When STA credentials are exhausted, the device falls back to AP mode. The SSID is derived from the ESP32 chip ID so multiple devices are distinguishable:

- Format: `AtomVM-XXXX` where `XXXX` is the low 16 bits of `:erlang.system_info(:esp32_chip_id)` in lowercase hex, zero-padded to 4 digits.
- Example: `AtomVM-a3f2`

The AP SSID is published alongside `:ap_mode` status on `:avm_pubsub` and shown on both the boot splash and the System Stats screen.

## Display state (ETS)

`OledDisplay.DisplayState` owns a single `:public` named ETS table. Any process can write; reads are lock-free.

| Namespace | Key | Value | Writer | Reader |
|---|---|---|---|---|
| `:weather` | `:locations` | `[%{name, lat, lon}, ...]` | `Weather` | `Screens.Weather` |
| `:weather` | `:units` | `:celsius` / `:fahrenheit` | `Weather` | `Screens.Weather` |
| `:weather` | `{:loc, name}` | `%{status, temp, humidity, icon, is_day, fetched_at}` | `Weather` | `Screens.Weather` |
| `:sysstats` | `:uptime_min` | integer | `SystemStats` | `SystemStats` |
| `:sysstats` | `:heap_kb` | integer / nil | `SystemStats` | `SystemStats` |
| `:sysstats` | `:min_heap_kb` | integer / nil | `SystemStats` | `SystemStats` |
| `:sysstats` | `:procs` | integer / nil | `SystemStats` | `SystemStats` |
| `:wifi` | `:status` | `{connected_bool, ip_tuple_or_nil, ap_ssid}` | `WiFi` | any screen |

## Weather

Weather data comes from [wttr.in](http://wttr.in) over **plain HTTP** (port 80). No API key required.

We use plain HTTP because TLS handshakes on ESP32-C3 exhaust the limited heap (~30 KB per connection), causing `out_of_memory` crashes. wttr.in returns a tiny pipe-delimited response (e.g. `+22°C|65%|Partly cloudy`) with `?format=%t|%h|%C` — no JSON, no TLS, ~30 bytes.

**Configuration:** compile-time in `config/config.exs`:
```elixir
config :oled_display, :weather,
  units: :celsius,                 # or :fahrenheit
  fetch_interval_ms: 900_000,    # 15 min
  locations: [
    %{name: "Toronto", lat: 43.6532, lon: -79.3832},
    %{name: "Tokyo",   lat: 35.6762, lon: 139.6503}
  ]
```

**Fetch cadence:** first fetch fires ~3 s after boot (or immediately on `:wifi_status -> :connected`). Subsequent fetches every `fetch_interval_ms` (±10 % jitter). Locations are fetched **sequentially** (one at a time) to keep peak heap usage low.

**Condition → icon mapping:** wttr.in English condition strings are matched keyword-by-keyword to the 10-icon set (clear→:sun, partly cloudy→:cloud_sun, rain→:rain1, etc.).

**Pubsub:**
- `{:weather_data, name}` — published after every successful fetch
- `{:weather_ready, name}` — published on the *first* success per location

**Failure handling:**
- WiFi down → `Screens.Weather.available?/1` returns false; screen skipped by auto-rotation
- HTTP/parse error → logged; ETS entry keeps last good values; `:status` set to `:error`
- Stale data (>30 min) → shown with `*` suffix in the location counter slot

**Adding a location:**
1. Run `tools/geocode.sh "City Name"` to look up lat/lon
2. Paste the printed map into `config/config.exs`
3. Recompile and flash

## Adding a new icon

1. Get XBM data (16×16 = 32 bytes) from Dhole or another source
2. Run `python3 tools/gen_icons.py` to regenerate all weather `.rgba` files from the embedded XBM source (writes to `assets/icons/`)
3. Add a `@<name> File.read!(Path.join(@icons_dir, "<name>.rgba"))` attribute and `get(:<name>)` clause in `icon_data.ex`
4. Use `IconData.get(:my_icon)` in screen render functions — returns `{:rgba8888, 16, 16, binary}`
5. For hollow outline icons, reference in a layout with a black background: `{:image, x, y, 0x000000, IconData.get(:my_icon)}`. Solid utility icons can use `:transparent`.

## Build & flash workflow

```bash
# 1. Source ESP-IDF (required for esptool.py)
. ~/.espressif/v5.5.3/esp-idf/export.sh

# 2. Fetch deps (one-time)
mix deps.get

# 3. Compile & pack .avm
mix atomvm.packbeam

# 4. Flash (offset 0x250000)
mix atomvm.esp32.flash --port /dev/ttyACM0 --baud 460800
```

The board resets automatically after flashing.

## Serial monitor

```bash
idf.py -p /dev/ttyACM0 monitor
# or: picocom /dev/ttyACM0 -b 115200
```

## Firmware prerequisites

- `ATOMVM_ELIXIR_SUPPORT=on` must be enabled in the AtomVM firmware build
- `atomgl` port driver component must be included
- ESP-IDF v5.5.3 at `~/.espressif/v5.5.3/esp-idf/`
- AtomVM source at `~/Dev/AtomVM`
- Erlang/OTP 28 + Elixir 1.19

## ExAtomVM warnings (safe to ignore)

During `mix atomvm.packbeam` you may see warnings like:

```
Warning: following modules or functions are not available on AtomVM:
* Elixir.GenServer:start_link/3
* Elixir.GenServer:call/2
* Elixir.Supervisor:child_spec/2
* Elixir.Supervisor:start_link/3
* erlang:phash2/2
```

These are false positives from ExAtomVM's static analysis. The modules ARE available in AtomVM — they just live in the pre-flashed boot AVM partition (standard library), not in `main.avm`. `GenServer`, `Supervisor`, `Agent`, etc. all work correctly on the device.

## Built-in random functions

AtomVM does **not** ship `:rand` (it is not in the boot AVM). Use the AtomVM-specific `:atomvm` module instead:

- `:atomvm.random/0` — returns a 32-bit unsigned integer (`0..4294967295`).

Example (jitter up to 10% of an interval):
```elixir
max_jitter = div(interval_ms, 10)
jitter = rem(:atomvm.random(), max_jitter)
```

Add `:atomvm` to `@compile {:no_warn_undefined, [...]}` in the calling module so ExAtomVM does not warn about it.


## `avm_pubsub` Elixir Interop Guide

**Overview**
Because Elixir runs on the Erlang VM, you can call Erlang modules directly by using their module names as atoms. The `avm_pubsub` module is a lightweight, MQTT-style PubSub server where topics are represented as lists, supporting single-level (`+`) and multi-level (`#`) wildcards.

### 1. Starting the PubSub Server

You can start the server either anonymously or with a registered local name for easier global reference.

```elixir
# Start anonymously
{:ok, pid} = :avm_pubsub.start()

# Start with a locally registered name
{:ok, _pid} = :avm_pubsub.start(:my_pubsub_server)
```

### 2. Basic Subscription and Publishing

Calling `sub/2` subscribes the calling process (`self()`) to the topic. Subscribers receive messages in the format: `{:pub, Topic, FromPid, Term}`.

```elixir
# Subscribe to a specific topic
:avm_pubsub.sub(:my_pubsub_server, [:rooms, :lobby])

# Publish a message (Returns {:ok, number_of_subscribers_reached})
{:ok, 1} = :avm_pubsub.pub(:my_pubsub_server, [:rooms, :lobby], "Hello, lobby!")

# Read the message from the process mailbox
receive do
  {:pub, topic, publisher_pid, payload} ->
    IO.puts("Received payload: #{inspect(payload)} on topic: #{inspect(topic)}")
end
```

### 3. Using Wildcards

Wildcards are represented using the atoms `:+` (single-level match) and `:#` (multi-level match).

```elixir
# --- Single-Level Wildcard (:+ ) ---
# Subscribes to any device's temperature readings
:avm_pubsub.sub(:my_pubsub_server, [:device, :+, :temp])

# Matches:
:avm_pubsub.pub(:my_pubsub_server, [:device, :sensor_1, :temp], 22.5)

# Does NOT match:
:avm_pubsub.pub(:my_pubsub_server, [:device, :sensor_1, :humidity], 60)

# --- Multi-Level Wildcard (:#) ---
# Subscribes to EVERYTHING under the :admin topic
:avm_pubsub.sub(:my_pubsub_server, [:admin, :#])

# Matches:
:avm_pubsub.pub(:my_pubsub_server, [:admin, :system, :cpu_warning], "CPU at 90%")
:avm_pubsub.pub(:my_pubsub_server, [:admin, :users, :new, 123], "User created")
```

### 4. Managing Other Processes

You can pass a specific Process ID (`Pid`) as the third argument to manage subscriptions for worker processes.

```elixir
# Assume worker_pid is a valid process ID
:avm_pubsub.sub(:my_pubsub_server, [:jobs], worker_pid)

# Publish a job directly to the worker
:avm_pubsub.pub(:my_pubsub_server, [:jobs], %{task: "send_email"})

# Unsubscribe the worker process
:avm_pubsub.unsub(:my_pubsub_server, [:jobs], worker_pid)
```

> **Note on AtomVM:** When compiling Elixir code for AtomVM microcontrollers, ensure you only use standard library features explicitly supported by AtomVM's subset of the full Erlang VM.
```s