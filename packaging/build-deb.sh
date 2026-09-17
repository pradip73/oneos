#!/bin/bash
# Builds the OneOS packages from the files the ISO ships.
#
#   packaging/build-deb.sh [OUTDIR]        default: out/packages
#
# WHAT THIS PRODUCES
#   oneos-desktop_<version>_all.deb          every OneOS file: the shell
#                                            applets, the helpers, the
#                                            branding, the policy
#   oneos-archive-keyring_<version>_all.deb  the repository's public key and
#                                            its sources entry -- only when
#                                            packaging/oneos-archive.asc exists
#
# WHY A PACKAGE, WHEN THE ISO ALREADY HAS THE FILES
# The ISO copies build/config/includes.chroot into the image as loose files.
# That works once. It cannot be updated: nothing owns those files, so nothing
# can replace them, and a machine installed from the ISO keeps whatever
# OneOS looked like the day it was downloaded -- forever. A package is the
# unit apt knows how to update, and a package is what the repository serves.
#
# The same tree feeds both. There is deliberately no second copy of anything
# to fall out of sync.
#
# WHY dpkg-deb AND NOT debhelper
# There is nothing to compile. debhelper's machinery earns its complexity on
# packages with build systems, tests and maintainer scripts; here it would
# be ten files of ceremony around a directory copy.

set -euo pipefail

readonly HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT="${HERE}/.."
readonly SRC="${ROOT}/build/config/includes.chroot"
readonly OUT="${1:-${ROOT}/out/packages}"

readonly BASE_VERSION="$(cat "${ROOT}/VERSION")"
# A repository build carries the date and commit, so each publish is newer
# than the last and apt sees it as an upgrade. A plain build is just VERSION.
if [ -n "${ONEOS_BUILD_ID:-}" ]; then
	VERSION="${BASE_VERSION}+${ONEOS_BUILD_ID}"
else
	VERSION="${BASE_VERSION}"
fi
readonly VERSION

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

command -v dpkg-deb >/dev/null 2>&1 || die "dpkg-deb not found (apt-get install dpkg)"
[ -d "$SRC" ] || die "no includes.chroot at $SRC"
mkdir -p "$OUT"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# --- oneos-desktop -------------------------------------------------------------
pkg="$work/oneos-desktop"
mkdir -p "$pkg/DEBIAN"

# Everything the ISO ships, except what only makes sense on the live medium:
# the live-config hook is for the live session, and the installer branding is
# useless on an installed system where Calamares is gone.
rsync -a "$SRC/" "$pkg/" \
	--exclude '/lib/live' \
	--exclude '/usr/share/calamares'

# The policy files are conffiles: dpkg will not overwrite a version the
# administrator has edited, which is the correct behaviour for /etc.
( cd "$pkg" && find etc -type f | sed 's|^|/|' ) > "$pkg/DEBIAN/conffiles"

installed_size=$(du -sk "$pkg" --exclude=DEBIAN | cut -f1)

cat > "$pkg/DEBIAN/control" <<EOF
Package: oneos-desktop
Version: ${VERSION}
Architecture: all
Maintainer: OneOS <oneos@localhost>
Installed-Size: ${installed_size}
Depends: plasma-desktop, kdialog, bubblewrap, wine, dbus-bin, nftables, xdg-user-dirs, libnotify-bin
Recommends: waydroid, unattended-upgrades, apparmor
Section: x11
Priority: optional
Homepage: https://github.com/pradip73/oneos
Description: OneOS desktop shell, helpers and policy
 The OneOS desktop: the Start menu, taskbar, quick settings, Control Panel
 and This Computer applets; the helpers behind Windows, Android and macOS
 programs; the hardware check; the firewall and update policy; and the
 branding.
 .
 This is the package the OneOS repository updates. Installing it on plain
 Debian trixie with Plasma gives that machine the OneOS desktop.
EOF

# Helpers must be executable in the package, exactly as the ISO hook makes
# them. A package is the place to get this right once.
find "$pkg/usr/bin" -type f -exec chmod 0755 {} +
find "$pkg" -type d -exec chmod 0755 {} +

# Refresh the caches that a desktop reads once and never re-reads on its own.
cat > "$pkg/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
	command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q || true
	command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
	# Firewall and sysctl policy take effect on the next boot; reloading a
	# live firewall from a package postinst is how remote sessions get cut.
fi
EOF
chmod 0755 "$pkg/DEBIAN/postinst"

log "Building oneos-desktop ${VERSION}"
dpkg-deb --root-owner-group --build "$pkg" "$OUT/oneos-desktop_${VERSION}_all.deb"

# --- oneos-archive-keyring -----------------------------------------------------
# Only when the public key exists. Until it does there is no repository to
# trust, and shipping a sources entry without a key would make apt refuse
# every update with an error the user cannot act on.
if [ -f "${HERE}/oneos-archive.asc" ]; then
	kr="$work/oneos-archive-keyring"
	mkdir -p "$kr/DEBIAN" "$kr/etc/apt/keyrings" "$kr/etc/apt/sources.list.d"

	command -v gpg >/dev/null 2>&1 || die "gpg needed to dearmor the archive key"
	gpg --dearmor < "${HERE}/oneos-archive.asc" > "$kr/etc/apt/keyrings/oneos-archive.gpg"
	chmod 0644 "$kr/etc/apt/keyrings/oneos-archive.gpg"

	cat > "$kr/etc/apt/sources.list.d/oneos.sources" <<'EOF'
# The OneOS repository: OneOS's own packages, signed with the OneOS key.
# Debian itself still comes from Debian; this only carries what is ours.
Types: deb
URIs: https://pradip73.github.io/oneos/apt
Suites: trixie
Components: main
Signed-By: /etc/apt/keyrings/oneos-archive.gpg
EOF

	cat > "$kr/DEBIAN/control" <<EOF
Package: oneos-archive-keyring
Version: ${VERSION}
Architecture: all
Maintainer: OneOS <oneos@localhost>
Section: misc
Priority: important
Description: OneOS repository signing key and sources entry
 The public key the OneOS repository signs with, and the apt sources entry
 that points at it. Removing this package stops OneOS updates.
EOF
	printf '/etc/apt/sources.list.d/oneos.sources\n' > "$kr/DEBIAN/conffiles"
	log "Building oneos-archive-keyring ${VERSION}"
	dpkg-deb --root-owner-group --build "$kr" "$OUT/oneos-archive-keyring_${VERSION}_all.deb"
else
	log "No packaging/oneos-archive.asc -- keyring package skipped (see docs/REPOSITORY.md)"
fi

log "Done"
ls -lh "$OUT"/*.deb
