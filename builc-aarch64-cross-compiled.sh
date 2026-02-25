#!/usr/bin/env bash
set -euo pipefail
nix build .#packages.x86_64-linux.dockerImage-aarch64
podman load -i result
