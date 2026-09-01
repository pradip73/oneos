#!/bin/sh
# Turn the glass off on hardware that cannot afford it.
#
# Live blur is recomputed every frame across every translucent surface. On the
# 4 GB integrated-graphics target that is the difference between a desktop that
# feels instant and one that stutters when a menu opens -- so the effect is a
# capability, not a constant.
#
# Runs at login. Cheap: two reads and, on capable machines, nothing else.

set -e
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/kwinrc"

mem_kb=$(sed -n 's/^MemTotal:[[:space:]]*\([0-9]*\).*/\1/p' /proc/meminfo)
mem_gb=$(( mem_kb / 1048576 ))

# llvmpipe means there is no GPU driver at all -- everything is being drawn on
# the CPU. Blur there is unusable, and this is the common case in a VM.
software_gl=0
if command -v glxinfo >/dev/null 2>&1; then
	glxinfo -B 2>/dev/null | grep -qi 'llvmpipe\|softpipe' && software_gl=1
fi

if [ "$mem_gb" -lt 4 ] || [ "$software_gl" -eq 1 ]; then
	command -v kwriteconfig6 >/dev/null 2>&1 || exit 0
	kwriteconfig6 --file "$CFG" --group Plugins --key blurEnabled false
	kwriteconfig6 --file "$CFG" --group Plugins --key contrastEnabled false
	echo "oneos: glass disabled (memory ${mem_gb} GB, software rendering ${software_gl})"
fi
