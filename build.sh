#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Build every image in build.yaml from pinned public sources, on macOS, using
# Apple's `container` runtime. No toolchain is installed on the host:
# everything except git runs inside zmkfirmware/zmk-build-arm.
#
#   ./build.sh
#
# Writes firmware/zmk_<artifact-name>.uf2 for each build.yaml entry and prints
# their SHA256.
#
# This is the local twin of the GitHub Actions build (.github/workflows), and
# reads the same inputs: config/west.yml for sources, build.yaml for what to
# build, config/ for keymaps and Kconfig, this repository as a Zephyr module.
# The one thing it does that CI cannot is apply patches/ to the board port.
#
# Requires: container (https://github.com/apple/container), ~4 GB free.
#
# Environment overrides:
#   NOCFREE_WS       west workspace      (default ~/.cache/zmk-nocfree/ws)
#   NOCFREE_OUT      artifact directory  (default firmware/ in this repository)
#   NOCFREE_MODULES  further ZMK modules, semicolon-separated, added to every
#                    build. This repository is mounted read-only at /repo
#                    inside the container, so a module here is /repo/<path>.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="${NOCFREE_WS:-$HOME/.cache/zmk-nocfree/ws}"
OUT="${NOCFREE_OUT:-$REPO/firmware}"

# Pinned by digest, not by :stable. The tag moves -- it is the last piece of
# the chain that config/west.yml already pins, and this exact image is the one
# shown to rebuild the right half byte-for-byte. zmkfirmware/zmk-build-arm:stable
# as of 2025-10-02; Zephyr SDK 0.16.9, arm-zephyr-eabi-gcc 12.2.0. Override
# with ZMK_BUILD_IMAGE to move it.
IMAGE="${ZMK_BUILD_IMAGE:-zmkfirmware/zmk-build-arm@sha256:edb1c953438c6f720ddb79c3762f3972013b7fbbaf4fff3592fc869983e7afc5}"

command -v container >/dev/null || { echo "container CLI not found: https://github.com/apple/container" >&2; exit 1; }
container system status >/dev/null 2>&1 || { echo "container services are not running: container system start" >&2; exit 1; }

# 1. Stage the west manifest repository. A copy rather than a mount, so the
#    workspace cannot write into this repository; replaced wholesale, so a
#    keymap deleted here does not linger there.
mkdir -p "$WS"
rm -rf "$WS/config"
cp -R "$REPO/config" "$WS/config"
WS="$(cd "$WS" && pwd)"

# 2. Build. -m/-c are worth setting explicitly: the runtime's defaults are
#    smaller than this build wants and a short build is a cheap thing to buy.
mkdir -p "$OUT"
container run --rm --arch arm64 -m 8g -c 8 \
    -v "$WS:/ws" \
    -v "$REPO:/repo:ro" \
    -v "$OUT:/out" \
    -w /ws \
    -e HOME=/tmp \
    -e GITHUB_WORKSPACE=/ws \
    -e "EXTRA_MODULES=/repo${NOCFREE_MODULES:+;$NOCFREE_MODULES}" \
    "$IMAGE" \
    bash -euo pipefail -c '
        # Some ZMK images set this, others ship the SDK without exporting it.
        if [ -z "${ZEPHYR_SDK_INSTALL_DIR:-}" ]; then
            sdk=$(ls -d /opt/zephyr-sdk-* 2>/dev/null | head -1)
            if [ -n "${sdk}" ]; then
                export ZEPHYR_SDK_INSTALL_DIR="${sdk}"
                export ZEPHYR_TOOLCHAIN_VARIANT=zephyr
            fi
        fi

        port=/ws/nocfree-and-zmk

        # Undo patches from the previous run first, so west can move the
        # checkout to a new pinned revision without tripping over them.
        if [ -d "${port}/.git" ]; then
            git -C "${port}" reset --hard --quiet
            git -C "${port}" clean -fdq
        fi

        if [ ! -d /ws/.west ]; then
            west init -l /ws/config
        fi
        west update --fetch-opt=--filter=tree:0
        west zephyr-export
        echo "==> board port at $(git -C "${port}" rev-parse --short HEAD)"

        # Local patches, applied in order: changes to the board port that
        # cannot be carried as user config. The pinned revision plus this
        # directory is the whole input set, so the build stays reproducible.
        shopt -s nullglob
        for patch in /repo/patches/*.patch; do
            if ! git -C "${port}" apply --check "${patch}" 2>/dev/null; then
                echo "patch does not apply to the pinned board port: ${patch##*/}" >&2
                exit 1
            fi
            git -C "${port}" apply "${patch}"
            echo "==> applied ${patch##*/}"
        done
        shopt -u nullglob

        # One line per build.yaml entry: artifact, board, cmake args.
        # ${GITHUB_WORKSPACE} in cmake-args expands here exactly as in CI.
        python3 - > /tmp/matrix <<"PY"
import os, yaml
for e in yaml.safe_load(open("/repo/build.yaml"))["include"]:
    args = os.path.expandvars(e.get("cmake-args", ""))
    print("\t".join([e["artifact-name"], e["board"], args]))
PY

        while IFS="	" read -r name board args; do
            echo "==> ${name}"
            # shellcheck disable=SC2086 -- args is a word list on purpose
            west build -p -s zmk/app -d "/ws/build/${name}" -b "${board}" \
                -- -DZMK_CONFIG=/ws/config -DZMK_EXTRA_MODULES="${EXTRA_MODULES}" ${args}
            cp "/ws/build/${name}/zephyr/zmk.uf2" "/out/zmk_${name}.uf2"
        done < /tmp/matrix
    '

echo
echo "Artifacts in $OUT"
(cd "$OUT" && shasum -a 256 zmk_*.uf2)
