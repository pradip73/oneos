#!/bin/bash
# Builds the OneOS kernel as Debian packages.
#
#   ./build-kernel.sh [VERSION]        default: the LTS pinned below
#
# WHAT THIS PRODUCES
# linux-image-<ver>-oneos and linux-headers-<ver>-oneos .deb files in ../out/kernel/,
# ready to drop into the image's package list.
#
# WHY BUILD A KERNEL AT ALL
# Two features the compatibility layers need are kernel-side, and Debian's
# stock kernel decides them for us:
#
#   CONFIG_ANDROID_BINDERFS  Waydroid does not run without it.
#   CONFIG_NTSYNC            Wine's fast path. Upstream only from 6.14.
#
# Debian does enable binderfs, so today's image works by luck rather than by
# design. Owning the config turns that into a guarantee -- and it is the
# difference between a distribution and a re-themed Debian.
#
# WHY THE CONFIG STARTS FROM DEBIAN'S
# Not from defconfig. defconfig produces a kernel that boots beautifully in a
# virtual machine and then fails on real laptops, because it omits most Wi-Fi
# chipsets, touchpads, webcams and power management. Debian's config already
# carries that breadth; oneos.config-fragment only states our deltas.

set -euo pipefail

readonly VERSION="${1:-6.12.48}"
readonly SERIES="v$(echo "$VERSION" | cut -d. -f1).x"
readonly LOCALVERSION="-oneos"

readonly HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly OUT="${HERE}/../out/kernel"
readonly WORK="${KERNEL_WORKDIR:-${HERE}/../.kernel-build}"

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

for t in gcc make bc flex bison rsync dpkg-deb curl; do
	command -v "$t" >/dev/null 2>&1 || die "missing build tool: $t
Install with:
  apt-get install -y build-essential fakeroot bc flex bison libssl-dev \\
                     libelf-dev rsync dwarves debhelper curl xz-utils"
done

free_gb=$(df -BG --output=avail "$(dirname "$WORK")" | tail -1 | tr -dc '0-9')
[ "${free_gb:-0}" -ge 30 ] || die "only ${free_gb} GB free; a kernel build with debug info needs ~35 GB"

mkdir -p "$WORK" "$OUT"
cd "$WORK"

# --- Source ------------------------------------------------------------------
readonly TARBALL="linux-${VERSION}.tar.xz"
if [ ! -f "$TARBALL" ]; then
	log "Fetching linux-${VERSION}"
	curl -fL --retry 3 -o "$TARBALL" \
		"https://cdn.kernel.org/pub/linux/kernel/${SERIES}/${TARBALL}" \
		|| die "could not download ${TARBALL} -- check the version exists in ${SERIES}"
fi

# The signature is what makes this a supply chain rather than a download. If
# the key is unavailable the build continues, but says so: an unverified kernel
# is a different thing from a verified one and the log should not blur them.
if command -v gpg >/dev/null 2>&1; then
	if [ ! -f "linux-${VERSION}.tar.sign" ]; then
		curl -fsL --retry 2 -o "linux-${VERSION}.tar.sign" \
			"https://cdn.kernel.org/pub/linux/kernel/${SERIES}/linux-${VERSION}.tar.sign" || true
	fi
	if [ -f "linux-${VERSION}.tar.sign" ] && gpg --list-keys >/dev/null 2>&1; then
		log "Verifying the tarball signature"
		if ! ( xz -cd "$TARBALL" | gpg --verify "linux-${VERSION}.tar.sign" - ) 2>/dev/null; then
			warn "SIGNATURE NOT VERIFIED -- no kernel.org key in this keyring."
			warn "The build continues, but this kernel is unverified source."
		else
			log "Signature verified"
		fi
	fi
fi

readonly SRC="${WORK}/linux-${VERSION}"
[ -d "$SRC" ] || { log "Extracting"; tar xf "$TARBALL"; }
cd "$SRC"

# --- Patch series ------------------------------------------------------------
# Ordered, and applied on top of a pristine tree -- never a fork. A fork means
# inheriting the kernel's whole security-backporting burden, which is the most
# common way small distributions die.
if compgen -G "${HERE}/patches/*.patch" >/dev/null; then
	for p in "${HERE}"/patches/*.patch; do
		if patch -p1 -N --dry-run < "$p" >/dev/null 2>&1; then
			log "Applying $(basename "$p")"
			patch -p1 < "$p"
		else
			warn "already applied or does not fit: $(basename "$p")"
		fi
	done
else
	warn "no patches in ${HERE}/patches -- see the ntsync note below"
fi

# --- Config ------------------------------------------------------------------
log "Fetching Debian's config for the base"
debcfg=""
if pkg=$(apt-cache depends linux-image-amd64 2>/dev/null | awk '/Depends:/{print $2; exit}') \
   && [ -n "$pkg" ]; then
	tmp=$(mktemp -d)
	if ( cd "$tmp" && apt-get download "$pkg" >/dev/null 2>&1 ); then
		deb=$(find "$tmp" -name '*.deb' | head -1)
		[ -n "$deb" ] && dpkg-deb -x "$deb" "$tmp/x" 2>/dev/null
		debcfg=$(find "$tmp/x/boot" -name 'config-*' 2>/dev/null | head -1)
	fi
fi

if [ -n "$debcfg" ] && [ -f "$debcfg" ]; then
	cp "$debcfg" .config
	log "Base config from $(basename "$debcfg")"
else
	# Honest fallback. Say plainly what this costs rather than quietly
	# producing a kernel that will disappoint on real hardware.
	warn "Could not obtain Debian's config; falling back to defconfig."
	warn "The result will boot in a VM and is likely to lack drivers for"
	warn "Wi-Fi, touchpads and power management on real laptops."
	make defconfig
fi

log "Merging oneos.config-fragment"
scripts/kconfig/merge_config.sh -m .config "${HERE}/oneos.config-fragment"

# Debian's config signs modules with a key we do not have, and enables debug
# info that triples build time and disk use. Neither belongs here.
scripts/config --disable MODULE_SIG_ALL \
               --disable DEBUG_INFO \
               --disable DEBUG_INFO_DWARF5 \
               --enable  DEBUG_INFO_NONE \
               --disable SYSTEM_TRUSTED_KEYS \
               --disable SYSTEM_REVOCATION_KEYS \
               --set-str LOCALVERSION "$LOCALVERSION"

make olddefconfig

# --- Did we actually get what we asked for? ----------------------------------
# merge_config warns about unknown symbols but does not fail, so a fragment
# naming an option this kernel has never heard of passes silently. Check.
log "Checking the options that matter"
check() {
	if grep -q "^$1=y" .config; then
		printf '  \033[32mon \033[0m %-28s %s\n' "$1" "$2"
	else
		printf '  \033[33moff\033[0m %-28s %s\n' "$1" "$2"
		return 1
	fi
}
check CONFIG_ANDROID_BINDERFS "Waydroid needs this" || die "binderfs is off; Android would not work"
check CONFIG_PSI              "low-memory responsiveness" || true
check CONFIG_ZRAM             "compressed swap on 4 GB machines" || true
check CONFIG_LRU_GEN          "better reclaim under pressure" || true
if ! check CONFIG_NTSYNC "Wine fast path"; then
	warn "ntsync is not in this kernel. It was upstreamed in 6.14 and this is"
	warn "${VERSION}; Wine falls back to its slower fsync path. To get it, put"
	warn "the backport in kernel/patches/ or move to a newer series."
fi

# --- Build -------------------------------------------------------------------
log "Building with $(nproc) jobs -- expect 40-90 minutes"
make -j"$(nproc)" bindeb-pkg LOCALVERSION="$LOCALVERSION" KDEB_PKGVERSION="${VERSION}-1oneos"

mv -f "${WORK}"/*.deb "$OUT"/ 2>/dev/null || die "the build produced no packages"

log "Done"
ls -lh "$OUT"/*.deb
cat <<EOF

To put this kernel in the image, replace linux-image-amd64 in
build/config/package-lists/oneos-base.list.chroot with the built package and
publish these files through the OneOS apt repository (docs/ARCHITECTURE.md 6.2).
Until that repository exists they can be installed by hand for testing.
EOF
