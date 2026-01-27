#!/usr/bin/env bash
set -euo pipefail
nix build .#packages.x86_64-linux.dockerImage
podman load -i result
