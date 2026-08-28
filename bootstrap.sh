#!/bin/bash
# OneOS bootstrap (Linux side). Invoked by setup.ps1, but can be run directly
# from inside WSL or any Debian host:
#
#   cd /mnt/c/Users/pradi/OneDrive/Desktop/oneaios && bash ./bootstrap.sh
#
# Installs build dependencies, copies the repo onto the Linux filesystem, and
# runs the ISO build. Safe to re-run.

set -euo pipefail

readonly SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEST="${HOME}/oneos"

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# --- Dependencies ------------------------------------------------------------
readonly DEPS=(live-build debootstrap xorriso squashfs-tools rsync ca-certificates)

missing=()
for pkg in "${DEPS[@]}"; do
	dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q "ok installed" || missing+=("${pkg}")
done

if (( ${#missing[@]} )); then
	log "Installing build dependencies: ${missing[*]}"
	sudo apt-get update
	sudo apt-get install -y --no-install-recommends "${missing[@]}"
else
	log "Build dependencies already present"
fi

# --- Copy onto the Linux filesystem ------------------------------------------
# This is not optional. live-build creates device nodes and bind-mounts inside
# a chroot; drvfs (/mnt/c) cannot represent those, and the build fails deep in
# with confusing errors. Copying is also far faster -- drvfs I/O is slow enough
# to add half an hour to the build.
log "Syncing repo to ${DEST}"
mkdir -p "${DEST}"
rsync -a --delete \
	--exclude 'out/' \
	--exclude '.git/' \
	--exclude 'build/.build/' \
	--exclude 'build/chroot/' \
	--exclude 'build/binary/' \
	--exclude 'build/cache/' \
	"${SRC}/" "${DEST}/"

chmod +x "${DEST}/build.sh" "${DEST}/build/auto/config"
find "${DEST}/build/config/hooks" -type f -name '*.hook.*' -exec chmod +x {} + 2>/dev/null || true

# --- Disk check before committing to a long build ----------------------------
free_gb=$(df -BG --output=avail "${DEST}" | tail -1 | tr -dc '0-9')
(( free_gb >= 15 )) || die "Only ${free_gb} GB free in the WSL filesystem; need 15 GB.
Free space in Windows, or move the WSL VHD to a larger drive."

# --- Build -------------------------------------------------------------------
log "Starting ISO build in ${DEST}"
log "First run takes 20-60 minutes and downloads ~1.5 GB. Output is verbose."
cd "${DEST}"
sudo ./build.sh build

log "Bootstrap complete. ISO is in ${DEST}/out/"
