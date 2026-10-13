# SPDX-License-Identifier: Apache-2.0
#
# Zephyr development container for the ESP32-S3-DevKitC-1-N16R8.
#
# Built from plain Ubuntu rather than from an upstream Zephyr image. The
# official chain installs the Zephyr SDK with `setup.sh -t all` - 35 GNU
# toolchains plus LLVM plus a VNC/Openbox desktop - and costs (compressed,
# amd64, measured 2026-10-11): ci-base 2.73 GB, ci 7.62 GB, zephyr-build
# 7.67 GB, which is 31.9 GB on disk. This project needs exactly one toolchain.
# Assembling the image here instead lands at roughly 1.5-2 GB.
#
# Four pins are coupled and must be bumped together:
#   ZEPHYR_TAG      must match the zephyr revision in ../west.yml
#   ZSDK_VERSION    must match that Zephyr release's SDK_VERSION
#                   (v4.4.0 pins 1.0.1)
#   ZSDK_TOOLCHAIN  the toolchain for the board's SoC
#   ZSDK_DIR        kept at the path the zephyr-build image used, so the
#                   compiler and its sysroot sit where they did in increment 1
#                   and the build output stays byte-comparable
ARG UBUNTU_TAG=24.04
ARG ZEPHYR_TAG=v4.4.0
ARG ZSDK_VERSION=1.0.1
ARG ZSDK_TOOLCHAIN=xtensa-espressif_esp32s3_zephyr-elf
ARG ZSDK_DIR=/opt/toolchains
ARG ZSDK_RELEASES=https://github.com/zephyrproject-rtos/sdk-ng/releases/download


# ---------------------------------------------------------------------------
# Stage 1: fetch the Zephyr SDK - the minimal bundle plus ONE toolchain.
# The tarballs are unpacked here and never reach the final image.
# ---------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_TAG} AS sdk

ARG ZSDK_VERSION
ARG ZSDK_TOOLCHAIN
ARG ZSDK_DIR
ARG ZSDK_RELEASES

# setup.sh refuses to start without cmake and, on Linux, wget: it checks both
# with `check_command` before doing anything else.
# The host-tools step (-h below) unpacks a Yocto standalone installer, which
# needs more than that and reports it only to a /dev/null that setup.sh
# redirects it to, so the prerequisites are listed here explicitly:
#   python3  "Error: The SDK needs a python installed", and the relocation
#            step runs python again to patch interpreter paths
#   file     "The command 'file' is required by the relocation script" -
#            `file` is not part of a minimal Ubuntu
#   xz       for the payload, `which` and `xargs` are already in the base image
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        cmake \
        file \
        python3 \
        wget \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR ${ZSDK_DIR}

# The minimal bundle is the SDK skeleton plus the host-tools installer: no
# toolchains at all (67 MB, against 2033 MB for the full _gnu bundle).
# sha256.sum covers every asset of the release, hence --ignore-missing.
RUN set -eux; \
    bundle="zephyr-sdk-${ZSDK_VERSION}_linux-x86_64_minimal.tar.xz"; \
    wget -q "${ZSDK_RELEASES}/v${ZSDK_VERSION}/${bundle}"; \
    wget -qO - "${ZSDK_RELEASES}/v${ZSDK_VERSION}/sha256.sum" \
        | sha256sum --check --ignore-missing; \
    tar xf "${bundle}"; \
    rm "${bundle}"

# -t downloads that single GNU toolchain from the same release and unpacks it
#    into gnu/<toolchain>,
# -h installs the bundled host tools (openocd, qemu, dtc) into hosttools/.
# -c is deliberately NOT passed here: it registers the CMake package under
#    $HOME, which in this stage is root's. It runs in the final stage instead,
#    as the container user.
# -o (symlinks for the pre-4.3 SDK layout) is not needed on Zephyr 4.4.
RUN "${ZSDK_DIR}/zephyr-sdk-${ZSDK_VERSION}/setup.sh" -t "${ZSDK_TOOLCHAIN}" -h


# ---------------------------------------------------------------------------
# Stage 2: the development image.
# ---------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_TAG}

ARG ZEPHYR_TAG
ARG ZSDK_VERSION
ARG ZSDK_DIR
ARG USERNAME=user
ARG USER_UID=1000
ARG USER_GID=1000

# Dependencies for a cross build of Zephyr, and nothing beyond that.
# Deliberately NOT installed: libsdl2-dev, gcc-multilib and g++-multilib
# (native_sim only), python3-tk (the guiconfig GUI only), dfu-util (unused on
# ESP32, which flashes over esptool), and the whole documentation toolchain.
# picocom is the serial console inside the container; sudo is needed by
# post-create.sh, which chowns the west workspace mountpoints.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        ccache \
        cmake \
        device-tree-compiler \
        file \
        g++ \
        gcc \
        git \
        gperf \
        make \
        ninja-build \
        picocom \
        python3 \
        python3-venv \
        sudo \
        wget \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Zephyr's Python tooling in a venv on PATH - Ubuntu 24.04 is PEP-668 managed,
# so a venv is not optional, and the zephyr-build image did the same.
# requirements-base.txt is Zephyr's build-only set; the full requirements.txt
# additionally pulls in the doc, test and compliance tooling, which this image
# has no use for. It is fetched from the pinned tag so it cannot drift away
# from west.yml.
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"
RUN set -eux; \
    python3 -m venv "${VIRTUAL_ENV}"; \
    wget -qO /tmp/requirements-base.txt \
        "https://raw.githubusercontent.com/zephyrproject-rtos/zephyr/${ZEPHYR_TAG}/scripts/requirements-base.txt"; \
    pip install --no-cache-dir -r /tmp/requirements-base.txt; \
    rm /tmp/requirements-base.txt

# The esp32 west runner (scripts/west_commands/runners/esp32.py) shells out to
# a bare `esptool` executable using esptool v5 subcommand syntax
# ("write-flash", "erase-flash", "--before default-reset"). esptool is NOT
# bundled in hal_espressif and NOT part of Zephyr's requirements*.txt - only
# pyserial is. It lands in the venv, which is on PATH.
RUN pip install --no-cache-dir "esptool~=5.5"

COPY --from=sdk ${ZSDK_DIR}/zephyr-sdk-${ZSDK_VERSION} ${ZSDK_DIR}/zephyr-sdk-${ZSDK_VERSION}

# Nothing from the SDK goes on PATH: Zephyr resolves the compiler and the host
# tools through its CMake package, and keeping PATH minimal keeps the build
# identical to increment 1.
# ZEPHYR_SDK_INSTALL_DIR is set explicitly so the build does not depend on the
# CMake package registry under $HOME surviving updateRemoteUserUID's remap.
# FindZephyr-sdk.cmake passes it as HINTS to find_package, which resolves
# <dir>/cmake/Zephyr-sdkConfig.cmake.
ENV ZEPHYR_TOOLCHAIN_VARIANT=zephyr
ENV ZEPHYR_SDK_INSTALL_DIR=${ZSDK_DIR}/zephyr-sdk-${ZSDK_VERSION}

# The container must not run as root, and the uid/gid have to be 1000 so
# devcontainer.json's updateRemoteUserUID can remap them onto the host user.
# Ubuntu 24.04 images already ship a user `ubuntu` at uid 1000, so that one has
# to go first.
# bash as the login shell, not Ubuntu's /bin/sh -> dash: dash is not linked
# against readline and has no `history` builtin, so arrow-up recalls nothing.
RUN set -eux; \
    userdel -r ubuntu 2>/dev/null || true; \
    groupadd -g "${USER_GID}" "${USERNAME}"; \
    useradd -m -u "${USER_UID}" -g "${USER_GID}" -s /bin/bash "${USERNAME}"; \
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "${USERNAME}" > "/etc/sudoers.d/${USERNAME}"; \
    chmod 0440 "/etc/sudoers.d/${USERNAME}"; \
    usermod -aG dialout "${USERNAME}"

# Persistent, immediately-flushed bash history.
# Two problems to solve: $HOME lives in the container's writable layer, so a
# rebuild discards the history; and bash only writes HISTFILE on a clean exit,
# which a closed VS Code window is not. `history -a` after every command fixes
# the second, and the /commandhistory named volume (see devcontainer.json) the
# first. Docker seeds a fresh named volume from the image, so the file and its
# ownership created here carry into the volume on first mount.
RUN mkdir -p /commandhistory \
    && touch /commandhistory/.bash_history \
    && chown -R "${USERNAME}:${USERNAME}" /commandhistory \
    && printf '%s\n' \
        "export HISTFILE=/commandhistory/.bash_history" \
        "export HISTSIZE=10000" \
        "export HISTFILESIZE=20000" \
        "shopt -s histappend" \
        "export PROMPT_COMMAND='history -a'" \
        >> "/home/${USERNAME}/.bashrc"

USER ${USERNAME}

# setup.sh -c, deferred from the builder stage: registers the SDK in the CMake
# package registry at $HOME/.cmake/packages/Zephyr-sdk.
RUN cmake -P "${ZSDK_DIR}/zephyr-sdk-${ZSDK_VERSION}/cmake/zephyr_sdk_export.cmake"
