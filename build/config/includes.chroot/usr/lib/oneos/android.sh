#!/bin/bash
# OneOS - bring Android up, and say exactly what went wrong if it will not.
#
#   . /usr/lib/oneos/android.sh
#   android_ensure_running || exit 1
#
# WHY ONE SHARED FUNCTION
# Three helpers (the demo, the .apk installer, the settings screen) each had
# their own copy of the same three steps -- one-time setup, start the
# container, start the session -- and each copy failed differently and said
# nothing useful when it did: "Could not start Android." The reason was in
# what waydroid printed, which every copy threw away.
#
# This keeps the output and puts it in the dialog. And it waits two minutes
# for the session, not thirty seconds: the first start after setup is
# Android booting for the first time, and on a 4 GB machine or a VM that
# takes well over a minute. Thirty seconds was giving up on a system that
# was fine.

android_err() {
	# title, details
	kdialog --title "Android apps" --detailederror "$1" "${2:-No further information was printed.}" 2>/dev/null \
		|| printf '%s\n%s\n' "$1" "${2:-}" >&2
}

android_session_running() {
	waydroid status 2>/dev/null | grep -q "Session:.*RUNNING"
}

android_ensure_running() {
	command -v waydroid >/dev/null 2>&1 || {
		android_err "Android app support is not installed on this system."; return 1; }

	if [ -r /usr/lib/oneos/hardware.sh ]; then
		. /usr/lib/oneos/hardware.sh
		oneos_hw_allows android || {
			android_err "Android apps cannot run on this computer." "$ONEOS_HW_REASON"; return 1; }
	fi

	# One-time setup: the Android system image, ~700 MB.
	if [ ! -f /var/lib/waydroid/waydroid.cfg ]; then
		kdialog --title "Android apps" --yesno "Android needs a one-time setup of about <b>700 MB</b> before any app can run.

Set it up now?" 2>/dev/null || return 1
		notify-send -a "OneOS" "Setting up Android" "Downloading the Android system. This takes a few minutes." 2>/dev/null
		local out
		if ! out=$(pkexec waydroid init 2>&1); then
			android_err "Android setup did not finish." "$(printf '%s' "$out" | tail -n 12)"
			return 1
		fi
	fi

	# The container: disabled at boot on purpose (1-1.5 GB of RAM), started
	# on the first request.
	if ! systemctl is-active --quiet waydroid-container.service; then
		local out
		if ! out=$(pkexec systemctl start waydroid-container.service 2>&1); then
			android_err "Could not start the Android container." \
				"$(printf '%s\n%s' "$out" "$(systemctl status waydroid-container.service 2>&1 | tail -n 8)")"
			return 1
		fi
	fi

	# The session, as the user.
	if ! android_session_running; then
		local slog; slog=$(mktemp)
		waydroid session start >"$slog" 2>&1 &
		local i
		for i in $(seq 1 120); do
			android_session_running && break
			sleep 1
		done
		if ! android_session_running; then
			android_err "Android did not start within two minutes." "$(tail -n 12 "$slog")"
			rm -f "$slog"; return 1
		fi
		rm -f "$slog"
	fi
	return 0
}
