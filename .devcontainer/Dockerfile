# SPDX-License-Identifier: Apache-2.0
#
# Zephyr development container for the ESP32-S3-DevKitC-1-N16R8.
#
# The base image provides everything needed to build Zephyr v4.4.0:
#   - Zephyr SDK 1.0.1 (installed with "-t all", so the
#     xtensa-espressif_esp32s3_zephyr-elf toolchain is present)
#   - west, inside a Python venv that is already on PATH
#   - Zephyr's scripts/requirements.txt
#   - user "user" (uid/gid 1000) with passwordless sudo
#
# Zephyr v4.4.0 pins SDK_VERSION 1.0.1, which is exactly what tag v0.29.4 ships.
# Keep these two in sync when bumping the Zephyr revision in west.yml.
ARG ZEPHYR_BUILD_TAG=v0.29.4
FROM ghcr.io/zephyrproject-rtos/zephyr-build:${ZEPHYR_BUILD_TAG}

USER root

# The esp32 west runner (scripts/west_commands/runners/esp32.py) shells out to a
# bare `esptool` executable using esptool v5 subcommand syntax ("write-flash",
# "erase-flash", "--before default-reset"). esptool is NOT bundled in
# hal_espressif and NOT part of Zephyr's requirements*.txt - only pyserial is.
# PATH already points at the image's Python venv, so this lands in the venv.
RUN pip install --no-cache-dir "esptool~=5.5"

# picocom: serial console inside the container.
# dialout: /dev/ttyACM0 is root:dialout mode 0660 on the host.
RUN apt-get update \
    && apt-get install -y --no-install-recommends picocom \
    && rm -rf /var/lib/apt/lists/* \
    && usermod -aG dialout user

# The base image creates `user` via useradd without -s, so the login shell is
# Ubuntu's default /bin/sh -> dash. dash is not linked against readline and has
# no `history` builtin, so arrow-up recalls nothing in an interactive terminal.
RUN usermod -s /bin/bash user

# Persistent, immediately-flushed bash history.
# Two problems to solve: $HOME lives in the container's writable layer, so a
# rebuild discards the history; and bash only writes HISTFILE on a clean exit,
# which a closed VS Code window is not. `history -a` after every command fixes
# the second, and the /commandhistory named volume (see devcontainer.json) the
# first. Docker seeds a fresh named volume from the image, so the file and its
# ownership created here carry into the volume on first mount.
RUN mkdir -p /commandhistory \
    && touch /commandhistory/.bash_history \
    && chown -R user:user /commandhistory \
    && printf '%s\n' \
        "export HISTFILE=/commandhistory/.bash_history" \
        "export HISTSIZE=10000" \
        "export HISTFILESIZE=20000" \
        "shopt -s histappend" \
        "export PROMPT_COMMAND='history -a'" \
        >> /home/user/.bashrc

USER user
