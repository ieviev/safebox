#!/usr/bin/env bash
set -euo pipefail
nix build .#packages.$(uname -m)-linux.dockerImage
podman load -i result
