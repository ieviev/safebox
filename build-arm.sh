#!/usr/bin/env bash
set -euo pipefail
nix build .#packages.aarch64-linux.dockerImage
podman load -i result
