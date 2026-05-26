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

## Project Structure

```
oled_display/
├── .gitignore
├── README.md
├── mix.exs                    # Mix project (ExAtomVM config)
├── lib/
│   └── oled_display.ex        # Main app (exports start/0)
```

## Iterating

1. Edit `lib/oled_display.ex`
2. `mix atomvm.esp32.flash --port /dev/ttyACM0`
3. The board resets automatically after flashing and runs the new app

## Dependencies

All runtime dependencies are provided by the boot AVM partition pre-flashed on the device:
- `I2C` — I2C bus driver
- `AVMPort` — Erlang port driver wrapper
- `Integer` — `Integer.to_string/1`
- `atomgl` display port driver (built into the firmware)

The custom `Elixir.OledDisplay.beam` is the only module in the main.avm partition.
