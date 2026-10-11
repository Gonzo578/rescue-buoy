#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Initialises the west workspace. Runs once per container creation, but is
# written to be idempotent: /workspaces and /workspaces/.west live in the
# container filesystem and are recreated on every rebuild, while
# /workspaces/deps persists in the named Docker volume.
set -euo pipefail

WORKSPACE_ROOT=/workspaces
MANIFEST_DIR=rescue-buoy

# Docker creates /workspaces and the volume mountpoint as root-owned, but
# `west init`/`west update` need to write there as the container user.
sudo chown "$(id -u):$(id -g)" "${WORKSPACE_ROOT}" "${WORKSPACE_ROOT}/deps"

cd "${WORKSPACE_ROOT}"

# T2 topology: this repository is the manifest repository.
if [ ! -d "${WORKSPACE_ROOT}/.west" ]; then
    echo "==> west init -l ${MANIFEST_DIR}"
    west init -l "${MANIFEST_DIR}"
else
    echo "==> west workspace already initialised, skipping init"
fi

echo "==> west update (shallow)"
west update --narrow -o=--depth=1

# Espressif HAL needs RF binary blobs that are not part of the git checkout.
echo "==> west blobs fetch hal_espressif"
west blobs fetch hal_espressif

# Registers the Zephyr CMake package so find_package(Zephyr) resolves.
echo "==> west zephyr-export"
west zephyr-export

cat <<'BANNER'

================================================================
 Workspace ready.

   cd /workspaces/rescue-buoy
   west build -p always -b esp32s3_devkitc/esp32s3/procpu \
              -S espressif-flash-16M .
   west flash
   picocom -b 115200 /dev/ttyACM0      # exit: Ctrl-A Ctrl-X

 Or use the VS Code tasks: "Zephyr: Build" / "Flash" / "Monitor".
================================================================

BANNER
