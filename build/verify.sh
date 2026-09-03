#!/bin/bash
# Verifies what actually ended up inside the image.
#
# WHY THIS EXISTS
# Every bug this project has shipped had the same shape: the build succeeded,
# the ISO was produced, and something was quietly missing from it.
#
#   - oneos-run-bundled was in the image but not executable, so VLC failed at
#     the click with a permissions error.
#   - Waydroid never installed, because an apt source named an architecture the
#     repository does not publish.
#   - Deleting /etc/resolv.conf in the first hook removed VLC, Notepad++,
#     F-Droid, 32-bit Wine and Waydroid at once -- 310 MB -- and the build
#     stayed green through three releases.
#
# Each time, someone had to download 2.6 GB, boot it and click something before
# anyone knew. This asserts those exact properties in a couple of seconds.
#
# It reads the squashfs that actually ships rather than live-build's chroot.
# The chroot is an intermediate that lb build does not leave behind, and even
# when it exists it is not necessarily what got packed. `unsquashfs -ll` lists
# permissions too, which matters: the worst bug here was a file that was
# present and not executable.

set -uo pipefail

readonly BUILD_DIR="${1:-build}"
readonly SQUASH="${BUILD_DIR}/binary/live/filesystem.squashfs"
readonly CHROOT="${BUILD_DIR}/chroot"

MANIFEST=$(mktemp); trap 'rm -f "$MANIFEST"' EXIT
MODE=""

if [ -f "$SQUASH" ] && command -v unsquashfs >/dev/null 2>&1; then
	MODE="squashfs"
	# -ll gives "mode owner size date squashfs-root/path"; strip the prefix so
	# lookups are by absolute path.
	unsquashfs -ll "$SQUASH" 2>/dev/null | sed 's|squashfs-root||' > "$MANIFEST"
elif [ -d "$CHROOT" ]; then
	MODE="chroot"
	( cd "$CHROOT" && find . -printf '%M %P\n' 2>/dev/null | sed 's| | /|2' ) > "$MANIFEST"
else
	echo "verify: neither $SQUASH nor $CHROOT exists -- nothing to check" >&2
	echo "verify: (run after build.sh, before lb clean)" >&2
	exit 0   # Not a build failure. Missing evidence is not evidence of a fault.
fi

echo "verifying the image via ${MODE} ($(wc -l < "$MANIFEST") entries)"
echo

pass=0; fail=0; warn=0
ok()   { printf '  \033[32mok\033[0m    %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
soft() { printf '  \033[33mwarn\033[0m  %s\n' "$1"; warn=$((warn+1)); }

# Exact path match on the last field, so /usr/bin/wine does not match
# /usr/bin/wineserver.
entry() { awk -v p="$1" '$NF == p {print; exit}' "$MANIFEST"; }

must_exist()  { if [ -n "$(entry "$1")" ]; then ok "$1"; else bad "missing: $1${2:+  ($2)}"; fi; }
should_exist(){ if [ -n "$(entry "$1")" ]; then ok "$1"; else soft "missing: $1${2:+  ($2)}"; fi; }

must_exec() {
	local e; e=$(entry "$1")
	if [ -z "$e" ]; then bad "missing: $1"
	elif [ "${e:0:1}" = "l" ]; then ok "$1 (symlink)"
	elif [[ ${e:0:10} == *x* ]]; then ok "$1 (executable)"
	# This exact case shipped: a helper present but not executable fails at the
	# user's click with an error that blames permissions rather than the build.
	else bad "NOT EXECUTABLE: $1 -- it will fail when clicked"
	fi
}

echo "== OneOS helpers =="
for h in oneos-about oneos-shortcuts oneos-welcome oneos-wine-run oneos-run-bundled \
         oneos-install-exe oneos-install-apk oneos-install-deb \
         oneos-windows-settings oneos-android-settings \
         oneos-demo-windows oneos-demo-android; do
	must_exec "/usr/bin/$h"
done

echo "== Shell applets =="
for a in launcher taskbar quicksettings controlpanel thiscomputer; do
	must_exist "/usr/share/plasma/plasmoids/org.oneos.${a}/contents/ui/main.qml" \
	           "the shell silently falls back to Plasma's"
done

echo "== Desktop icons =="
for d in oneos-about oneos-control-panel oneos-files oneos-trash oneos-account; do
	must_exist "/etc/skel/Desktop/${d}.desktop"
done

echo "== Compatibility layers =="
must_exist   "/usr/bin/wine"     "Windows programs will not run"
must_exist   "/usr/bin/bwrap"    "Windows programs would run UNSANDBOXED"
should_exist "/usr/bin/waydroid" "no Android support in this image"

echo "== Preinstalled Windows programs =="
# The 310 MB that vanished, named individually so a report says which.
BUNDLE="/etc/skel/.local/share/oneos/prefixes/oneos-bundled/drive_c"
should_exist "${BUNDLE}"                                   "no Wine prefix was built"
should_exist "${BUNDLE}/Program Files/VLC/vlc.exe"         "VLC did not download"
should_exist "${BUNDLE}/Program Files/Notepad++/notepad++.exe" "Notepad++ did not download"
should_exist "/usr/share/oneos/android-apps/fdroid.apk"    "F-Droid was not staged"

echo "== Branding =="
must_exist   "/etc/xdg/kdeglobals" "accent colour not applied"
should_exist "/usr/share/plymouth/themes/oneos/logo.png" "boot splash artwork not rendered"
should_exist "/usr/share/wallpapers/OneOS/contents/images/1920x1080.png" "wallpaper not rendered"

echo "== Firmware for real hardware =="
# A laptop with no Wi-Fi firmware reaches a desktop with no way online, and
# nothing on screen explains why.
for fw in iwlwifi brcm rtl_nic mediatek; do
	if grep -qi "/lib/firmware/[^ ]*${fw}" "$MANIFEST"; then
		ok "firmware: ${fw}"
	else
		soft "firmware missing: ${fw}"
	fi
done

echo
printf '%d passed, %d warnings, %d FAILURES\n' "$pass" "$warn" "$fail"
[ "$fail" -eq 0 ] || {
	echo "verify: the image is missing something it must have." >&2
	exit 1
}
