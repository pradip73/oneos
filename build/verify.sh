#!/bin/bash
# Verifies what actually ended up inside the image.
#
# WHY THIS EXISTS
# Every bug this project has shipped so far had the same shape: the build
# succeeded, the ISO was produced, and something was quietly missing from it.
#
#   - oneos-run-bundled was in the image but not executable, so VLC failed at
#     the click with a permissions error.
#   - Waydroid never installed because an apt source named an architecture the
#     repository does not publish.
#   - Deleting /etc/resolv.conf in the first hook silently removed VLC,
#     Notepad++, F-Droid, 32-bit Wine and Waydroid from the image at once --
#     310 MB, and the build stayed green.
#
# In each case a person had to download 2.6 GB, boot it, and click something
# before anyone knew. This asserts the things that were wrong before, against
# the chroot that live-build leaves on disk, in about a second.
#
# Run from the repository root after build.sh. Exits non-zero if a MUST fails.

set -uo pipefail

readonly CHROOT="${1:-build/chroot}"

pass=0; fail=0; warn=0

ok()   { printf '  \033[32mok\033[0m    %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
soft() { printf '  \033[33mwarn\033[0m  %s\n' "$1"; warn=$((warn+1)); }

have()      { [ -e "${CHROOT}$1" ]; }
executable(){ [ -x "${CHROOT}$1" ]; }

must_exist() { if have "$1"; then ok "$1"; else bad "missing: $1${2:+  ($2)}"; fi; }
should_exist(){ if have "$1"; then ok "$1"; else soft "missing: $1${2:+  ($2)}"; fi; }

must_exec() {
	if ! have "$1"; then bad "missing: $1"
	elif executable "$1"; then ok "$1 (executable)"
	# This exact case shipped once. A helper that exists but cannot run fails
	# at the user's click, with an error that blames permissions rather than us.
	else bad "NOT EXECUTABLE: $1 -- it will fail when clicked"
	fi
}

[ -d "$CHROOT" ] || { echo "verify: no chroot at $CHROOT (run after build.sh)" >&2; exit 2; }

echo "== OneOS helpers =="
for h in oneos-about oneos-shortcuts oneos-welcome oneos-wine-run oneos-run-bundled \
         oneos-install-exe oneos-install-apk oneos-install-deb \
         oneos-windows-settings oneos-android-settings \
         oneos-demo-windows oneos-demo-android; do
	must_exec "/usr/bin/$h"
done

echo "== Shell applets =="
for a in launcher taskbar quicksettings controlpanel thiscomputer; do
	must_exist "/usr/share/plasma/plasmoids/org.oneos.${a}/contents/ui/main.qml" "the shell falls back to Plasma's"
done

echo "== Desktop icons =="
for d in oneos-about oneos-control-panel oneos-files oneos-trash oneos-account; do
	must_exist "/etc/skel/Desktop/${d}.desktop"
done

echo "== Compatibility layers =="
must_exist  "/usr/bin/wine"     "Windows programs will not run"
must_exist  "/usr/bin/bwrap"    "Windows programs would run UNSANDBOXED"
should_exist "/usr/bin/waydroid" "no Android support in this image"

echo "== Preinstalled Windows programs =="
# The 310 MB that vanished. Named individually so the report says which.
should_exist "/etc/skel/.local/share/oneos/prefixes/oneos-bundled/drive_c" "no Wine prefix was built"
should_exist "/etc/skel/.local/share/oneos/prefixes/oneos-bundled/drive_c/Program Files/VLC/vlc.exe" "VLC did not download"
should_exist "/etc/skel/.local/share/oneos/prefixes/oneos-bundled/drive_c/Program Files/Notepad++/notepad++.exe" "Notepad++ did not download"
should_exist "/usr/share/oneos/android-apps/fdroid.apk" "F-Droid was not staged"

echo "== Branding =="
must_exist   "/usr/share/plasma/plasmoids/org.oneos.launcher/metadata.json"
should_exist "/usr/share/plymouth/themes/oneos/logo.png" "boot splash artwork not rendered"
should_exist "/usr/share/wallpapers/OneOS/contents/images/1920x1080.png" "wallpaper not rendered"
must_exist   "/etc/xdg/kdeglobals" "accent colour not applied"

echo "== Firmware for real hardware =="
# A laptop with no Wi-Fi firmware boots to a desktop with no way online, and
# nothing on screen explains why.
for fw in iwlwifi brcm rtl_nic mediatek; do
	if find "${CHROOT}/lib/firmware" -maxdepth 1 -iname "*${fw}*" 2>/dev/null | grep -q .; then
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
