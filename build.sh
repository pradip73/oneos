#!/bin/bash
# OneOS ISO build orchestrator.
#
#   Usage:  sudo ./build.sh [clean|build|rebuild]
#
# MUST be run on a Debian or Debian-derived Linux system (WSL2 Debian is fine
# for producing the ISO; you cannot build a Linux ISO from Windows). Requires
# root because live-build creates and mounts a chroot.
#
# Output: out/oneos-<version>-amd64.hybrid.iso
#
# See docs/BUILD-PLAN.md Phase 1 for what this ISO is and is not.

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BUILD_DIR="${REPO_ROOT}/build"
readonly OUT_DIR="${REPO_ROOT}/out"
readonly VERSION="$(cat "${REPO_ROOT}/VERSION")"

# Minimum free space for an ISO build.
#
# The finished ISO is only ~1.5 GB, but the build holds several uncompressed
# stages on disk simultaneously:
#
#   apt cache (compressed .deb)      ~1.2 GB
#   chroot/    (unpacked rootfs)     ~2.5 GB   <- .deb unpacks to 2-3x its size
#   binary/    (staging + squashfs)  ~2.0 GB
#   final ISO                        ~1.5 GB
#   ------------------------------------------
#   peak concurrent                  ~7-8 GB
#
# 15 GB gives comfortable headroom for a failed build leaving stages behind.
#
# NOTE: building the custom kernel (Phase 1b, see kernel/README.md) is a
# separate job and needs far more -- roughly 35 GB with debug info and BTF
# enabled. Do not size your build volume from this number alone.
readonly REQUIRED_FREE_GB=15

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

preflight() {
	log "Preflight checks"

	[[ ${EUID} -eq 0 ]] || die "Must run as root (live-build mounts a chroot). Use: sudo ./build.sh"

	# live-build genuinely does not work anywhere but Debian-family hosts.
	[[ -f /etc/debian_version ]] || die "This must run on a Debian-based host. Detected: $(uname -a)"

	local missing=()
	for tool in lb debootstrap xorriso mksquashfs rsync; do
		command -v "${tool}" >/dev/null 2>&1 || missing+=("${tool}")
	done
	if (( ${#missing[@]} )); then
		die "Missing tools: ${missing[*]}
Install with:
  apt update && apt install -y live-build debootstrap xorriso squashfs-tools rsync"
	fi

	local free_gb
	free_gb=$(df -BG --output=avail "${REPO_ROOT}" | tail -1 | tr -dc '0-9')
	if (( free_gb < REQUIRED_FREE_GB )); then
		die "Only ${free_gb} GB free at ${REPO_ROOT}; need at least ${REQUIRED_FREE_GB} GB.
Move the build tree to a larger volume."
	fi

	# live-build writes device nodes and mounts; a Windows-mounted path (drvfs
	# under WSL) cannot support this and fails deep into the build with
	# confusing errors. Catch it here instead.
	local fstype
	fstype=$(stat -f -c %T "${REPO_ROOT}")
	if [[ ${fstype} == "9p" || ${fstype} == "v9fs" || ${REPO_ROOT} == /mnt/[a-z]/* ]]; then
		die "The build tree is on a Windows-mounted filesystem (${REPO_ROOT}).
live-build requires a real Linux filesystem for the chroot.
Copy this repo into the Linux filesystem first, e.g. ~/oneos, and build there."
	fi

	log "Preflight OK (free: ${free_gb} GB, version: ${VERSION})"
}

do_clean() {
	log "Cleaning build tree"
	cd "${BUILD_DIR}"
	lb clean --purge || warn "lb clean reported errors (safe to ignore on a fresh tree)"
	rm -rf "${BUILD_DIR}/.build" "${BUILD_DIR}/chroot" "${BUILD_DIR}/binary" \
	       "${BUILD_DIR}/cache/stages" 2>/dev/null || true
}

do_build() {
	preflight
	mkdir -p "${OUT_DIR}"
	cd "${BUILD_DIR}"

	log "Configuring (lb config)"
	lb config

	log "Building ISO -- this takes 20-60 minutes on first run"
	log "The apt cache is preserved between builds; later builds are much faster."

	# live-build does NOT write a build.log of its own -- it logs to stdout and
	# stderr and exits with a bare status. Tee it so the full output is visible
	# in the CI job (where the failure has to be diagnosed) and is also kept on
	# disk for the artifact upload.
	# pipefail is already set at the top of the script, so a failing lb build
	# is caught even though tee succeeds.
	if ! lb build 2>&1 | tee "${BUILD_DIR}/build.log"; then
		echo "--------------------------------------------------------------"
		warn "lb build failed. The live-build output above is the full log."
		warn "The last error line is usually the real cause; live-build prints"
		warn "a lot of noise after it."
		echo "--------------------------------------------------------------"
		die "Build failed."
	fi

	local artifact
	artifact=$(find "${BUILD_DIR}" -maxdepth 1 -name '*.iso' -print -quit)
	[[ -n ${artifact} ]] || die "Build finished but produced no ISO. Check ${BUILD_DIR}/build.log"

	local final="${OUT_DIR}/oneos-${VERSION}-amd64.hybrid.iso"
	mv "${artifact}" "${final}"
	( cd "${OUT_DIR}" && sha256sum "$(basename "${final}")" > "$(basename "${final}").sha256" )

	log "Done."
	printf '\n  ISO:    %s\n  Size:   %s\n  SHA256: %s\n\n' \
		"${final}" \
		"$(du -h "${final}" | cut -f1)" \
		"$(cut -d' ' -f1 "${final}.sha256")"
	cat <<-'EOF'
	Next steps:
	  1. Write to USB:   dd if=out/oneos-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
	     (on Windows, use Rufus or balenaEtcher in DD/image mode)
	  2. Boot a test machine. You should reach a text login as user 'nova'.
	  3. This ISO has NO desktop. That is expected -- see docs/BUILD-PLAN.md Phase 1.
	EOF
}

case "${1:-build}" in
	clean)   do_clean ;;
	build)   do_build ;;
	rebuild) do_clean; do_build ;;
	*)       die "Usage: $0 [clean|build|rebuild]" ;;
esac
