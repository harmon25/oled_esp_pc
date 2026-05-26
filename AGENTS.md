# OledDisplay — Agent instructions

Single-module AtomVM app (`lib/oled_display.ex`) for SSD1306 OLED on ESP32-C3. No tests, no CI.

## App entrypoint

- `OledDisplay.start/0` — called by AtomVM on boot (configured in mix.exs `atomvm: [start: OledDisplay]`)
- `OledDisplay` is the only module packed into `main.avm`; all runtime deps (I2C, AVMPort, atomgl) live in the pre-flashed boot AVM partition

## Hardware

- I2C: GPIO 3 (SDA), GPIO 4 (SCL), 400 kHz
- Display: SSD1306, 128×64

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
