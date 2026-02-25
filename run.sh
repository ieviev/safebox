#!/usr/bin/env bash
set -euo pipefail

mounts=(
	-v "${HOME}/.claude.json:/home/claude/.claude.json"
	-v "${HOME}/.claude/:/home/claude/.claude/"
	-v "${HOME}/.npm/:/home/claude/.npm/"
	-v "${PWD}:${PWD}"
)

podman run \
	"${mounts[@]}" \
	-w "$PWD" \
	--rm \
	--name "safebox-$(date +%s)" \
	-ti \
	--user claude \
	--userns=keep-id:uid=$(id -u),gid=$(id -g) \
	"safebox" "$@" \
