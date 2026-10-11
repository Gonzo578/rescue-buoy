# rescue-buoy

Zephyr RTOS firmware for an **ESP32-S3-DevKitC-1-N16R8** (16 MB flash, 8 MB octal PSRAM).

The whole toolchain lives in a VS Code Dev Container, so nothing has to be installed on the
host beyond Docker and the Dev Containers extension.

| | |
| --- | --- |
| Zephyr | `v4.4.0` (pinned in [`west.yml`](west.yml)) |
| Zephyr SDK | `1.0.1` (from the base image, matches Zephyr's `SDK_VERSION`) |
| Board target | `esp32s3_devkitc/esp32s3/procpu` |
| Console | `uart0` @ 115200 baud, over the **UART** USB port (CH343 bridge) |

## Prerequisites (host)

1. **Docker** — must be running, and your user must be in the `docker` group.
2. **VS Code** with the **Dev Containers** extension (`ms-vscode-remote.remote-containers`).
3. Your user must be in the **`dialout`** group to reach the board's serial port:
   ```bash
   groups | grep -q dialout || sudo usermod -aG dialout "$USER"   # then log out and back in
   ```

No compiler, no Python packages, no SDK on the host.

## Hardware setup

Connect a USB cable to the DevKit's **UART** port (the one that enumerates as `/dev/ttyACM0`
via the CH343 bridge). This single cable handles both flashing and the serial console.

The DevKitC-1 has no plain GPIO LED — its only onboard LED is an addressable WS2812 RGB LED,
which Zephyr 4.4 cannot drive without an SPI bit-banging workaround. So wire up an external LED:

```
GPIO2 ──[ 330 Ω ]──▶|── GND
                   LED
```

`GPIO2` → resistor → LED anode (long leg); LED cathode (short leg) → `GND`.
To use a different pin, edit [`boards/esp32s3_devkitc_esp32s3_procpu.overlay`](boards/esp32s3_devkitc_esp32s3_procpu.overlay);
that file also lists the pins that are **not** safe to use on this module.

## Getting started

1. **Plug the board in first.** The container claims `/dev/ttyACM0` at startup via
   `--device=`, so Docker refuses to start if the node does not exist.
   ```bash
   ls -l /dev/ttyACM0
   ```
2. Open this folder in VS Code and run **Dev Containers: Reopen in Container**.
   The first run builds the image and runs `.devcontainer/post-create.sh`, which does
   `west init` / `west update` / `west blobs fetch hal_espressif`. Budget **10–15 minutes**.
3. Build, flash and watch the console:
   ```bash
   west build -p always -b esp32s3_devkitc/esp32s3/procpu -S espressif-flash-16M .
   west flash
   picocom -b 115200 /dev/ttyACM0        # exit: Ctrl-A Ctrl-X
   ```
   The same three steps are available as the VS Code tasks **Zephyr: Build**,
   **Zephyr: Flash** and **Zephyr: Monitor**.

Expected output:

```
*** Booting Zephyr OS build v4.4.0 ***
[00:00:00.123,000] <inf> main: Hello World! esp32s3_devkitc/esp32s3/procpu
[00:00:00.123,000] <inf> main: Blinking LED on gpio@60004000 pin 2 every 500 ms
```

…and the LED blinks at 1 Hz.

## Permissions and file ownership

The container does **not** run as root. The base image provides a user `user`
(uid 1000, gid 1000), and `devcontainer.json` sets `remoteUser: "user"` plus
`updateRemoteUserUID: true`, which remaps that user to the *host* user's
uid:gid when the container is created.

The practical consequence: everything the container writes into this directory
-- `build/` above all -- stays owned by your host user and is removable
**without sudo**:

```bash
rm -rf build          # works from the host, no sudo
```

Note that deletion rights follow the owning **uid** plus write permission on
the parent directory; the gid only affects what `ls -l` reports.

Two things do *not* live in this directory and are therefore not removed that way:

| What | How to remove it |
| --- | --- |
| Zephyr + modules (`deps/`, a named Docker volume) | `docker volume rm rescue-buoy-west-deps` |
| The container image (SDK, toolchain) | `docker rmi` / `docker system prune` |

Both work without sudo because your user is in the `docker` group.

> **Pitfall:** never run the build under `sudo` *inside* the container. Files it
> creates in the bind mount end up root-owned on the host and then really do
> need sudo to delete. `.devcontainer/post-create.sh` uses `sudo chown` only on
> `/workspaces` and `/workspaces/deps` -- container-internal paths and the
> volume -- never on this repository.

## Repository layout

```
.
├── CMakeLists.txt      Zephyr application (the repo root IS the application)
├── prj.conf            Kconfig fragment
├── west.yml            West manifest, pins Zephyr v4.4.0
├── boards/             Board-specific devicetree overlays
├── src/                Application sources
├── tests/              Twister tests
├── docs/Arch           Architecture documentation
├── docs/Reqm           Requirements
└── .devcontainer/      Dev container definition
```

Zephyr and its modules are **not** part of this repository. `west` fetches them into
`/workspaces/deps` inside the container, which is a named Docker volume
(`rescue-buoy-west-deps`) so it survives container rebuilds.

The `west.yml` manifest uses `import: name-allowlist` to clone only `hal_espressif` and
`picolibc` instead of the full ~8 GB Zephyr workspace. If a build ever fails because a module
is missing, add its name to that allowlist and re-run `west update`.

## Build variants

The `espressif-flash-16M` snippet matches the N16R8's 16 MB flash. The 8 MB octal PSRAM is
**not** enabled by default — add the snippet when you need it:

```bash
west build -b esp32s3_devkitc/esp32s3/procpu \
           -S espressif-flash-16M -S espressif-psram-8M .
```

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Container will not start, `error gathering device information` | Board was not plugged in. Plug it in, then reopen in container. |
| Port is `/dev/ttyUSB0`, not `/dev/ttyACM0` | Older DevKit revision using a CP210x bridge. Update `runArgs` and `ESPTOOL_PORT` in `.devcontainer/devcontainer.json`. |
| `Permission denied: '/dev/ttyACM0'` in the container | `dialout` GID mismatch. Compare `stat -c '%g' /dev/ttyACM0` with `getent group dialout` inside the container; if they differ, add `groupmod -g <host-gid> dialout` to `.devcontainer/Dockerfile`. |
| `Failed to connect to ESP32-S3` | Hold **BOOT**, tap **RESET**, release **BOOT**, then `west flash` again. |
| `led0 devicetree alias is not defined` | The overlay filename must match the board target with `/` replaced by `_`. |
| Console shows garbage | Console is 115200 baud; 921600 is the *flash* baud rate. |
| Device node changes between replugs | Replace `--device=/dev/ttyACM0` with `--device-cgroup-rule=c 166:* rmw` plus a `/dev` bind mount, or add a host udev rule for a stable symlink. |
