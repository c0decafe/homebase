#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:-ghcr.io/c0decafe/homebase:latest}"
SMOKE_GITHUB_USER="${SMOKE_GITHUB_USER:-${GITHUB_USER:-c0decafe}}"

log() { echo "[smoke] $*"; }
run() { log "$*"; bash -lc "$*"; }

run "docker run --rm ${IMAGE} id"
run "docker run --rm ${IMAGE} cat /etc/os-release"
run "docker run --rm ${IMAGE} bash -lc 'stat -c \"%U:%G %a %n\" /home/vscode /workspaces'"
run "docker run --rm ${IMAGE} bash -lc 'sudo -n true && ls -l /bin/sudo'"
run "docker run --rm -e GITHUB_USER=${SMOKE_GITHUB_USER} ${IMAGE} bash -lc 'sudo /usr/local/share/ssh-init.sh && ls -al /home/vscode/.ssh'"
run "docker run --rm -e GITHUB_USER=${SMOKE_GITHUB_USER} ${IMAGE} bash -lc 'sudo /usr/local/share/ssh-init.sh && ss -lnpt | grep :2222'"

echo "[smoke] All checks passed"
