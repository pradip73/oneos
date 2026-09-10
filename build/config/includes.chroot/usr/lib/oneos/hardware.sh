#!/bin/sh
# OneOS - hardware capability check, shared by every helper that gates on it.
#
# WHY
# OneOS's floor is 2 GB and two cores. The desktop, Windows programs and the
# macOS command line all fit there. The Android container does not: Waydroid
# runs a whole Android system in memory, 1-1.5 GB before a single app opens,
# and on a 2 GB machine that means the desktop swaps itself to death and the
# user concludes the OS is broken. It is not broken. It was asked to do
# something the machine cannot hold.
#
# So rather than let that happen, every layer states its own requirements
# here, in one place, and each helper asks before proceeding. The answer is
# always accompanied by the reason, because "not available" without a why
# teaches people that the OS is arbitrary.
#
# Computed on demand from /proc rather than cached by a boot service: it
# costs three file reads, hardware does not change mid-session, and a cache
# is one more thing that can be stale after a disk is moved to another box.
#
# Usage:
#     . /usr/lib/oneos/hardware.sh
#     oneos_hw_allows android || { echo "$ONEOS_HW_REASON"; exit 1; }

# --- Thresholds, in MB of MemTotal -------------------------------------------
# A "2 GB" machine reports about 1950 MB after the kernel and firmware take
# their share; a "4 GB" one about 3900. The numbers below sit under the
# nominal figure on purpose so a 2 GB machine is treated as a 2 GB machine.
ONEOS_HW_MIN_BASE=1700       # below this the desktop itself is a poor fit
ONEOS_HW_MIN_ANDROID=2800    # 3 GB nominal: container plus a usable desktop
ONEOS_HW_MIN_CORES=2

ONEOS_HW_RAM_MB=$(( $(sed -n 's/^MemTotal:[[:space:]]*\([0-9]*\).*/\1/p' /proc/meminfo) / 1024 ))
ONEOS_HW_CORES=$(nproc 2>/dev/null || echo 1)
ONEOS_HW_ARCH=$(uname -m)

# Free space on the volume holding the user's data, in MB. Android's system
# image alone is ~700 MB downloaded and ~2 GB unpacked.
ONEOS_HW_FREE_MB=$(df -Pm "${HOME:-/}" 2>/dev/null | awk 'NR==2 {print $4}')
: "${ONEOS_HW_FREE_MB:=0}"

# Human-readable, rounded the way a person would say it.
ONEOS_HW_RAM_GB=$(( (ONEOS_HW_RAM_MB + 512) / 1024 ))

# oneos_hw_allows LAYER
#   Returns 0 if the layer is a sensible fit for this machine. On 1, sets
#   ONEOS_HW_REASON to a sentence a non-technical person can act on.
oneos_hw_allows() {
	ONEOS_HW_REASON=""
	case "$1" in
	base)
		if [ "$ONEOS_HW_RAM_MB" -lt "$ONEOS_HW_MIN_BASE" ]; then
			ONEOS_HW_REASON="This computer has ${ONEOS_HW_RAM_GB} GB of memory. OneOS needs at least 2 GB to run well."
			return 1
		fi
		if [ "$ONEOS_HW_CORES" -lt "$ONEOS_HW_MIN_CORES" ]; then
			ONEOS_HW_REASON="This computer has a single-core processor. OneOS needs at least two cores."
			return 1
		fi
		;;
	windows)
		# Wine itself is light. A 2 GB machine runs one modest program at a
		# time; it is the base requirement, not a stricter one.
		oneos_hw_allows base || return 1
		;;
	android)
		if [ "$ONEOS_HW_RAM_MB" -lt "$ONEOS_HW_MIN_ANDROID" ]; then
			ONEOS_HW_REASON="Android apps need at least 3 GB of memory, and this computer has ${ONEOS_HW_RAM_GB} GB. Android runs as a complete second system inside OneOS and would leave nothing for the desktop."
			return 1
		fi
		if [ "$ONEOS_HW_FREE_MB" -lt 3000 ]; then
			ONEOS_HW_REASON="Android needs about 3 GB of free disk space for its system image, and this computer has $(( ONEOS_HW_FREE_MB / 1024 )) GB free."
			return 1
		fi
		;;
	mac)
		# Darling is a userspace runtime and, without the GUI stack, modest.
		# The only hard requirement is the architecture.
		if [ "$ONEOS_HW_ARCH" != "x86_64" ]; then
			ONEOS_HW_REASON="macOS programs need a 64-bit Intel or AMD processor."
			return 1
		fi
		oneos_hw_allows base || return 1
		;;
	*)
		ONEOS_HW_REASON="unknown layer: $1"
		return 1
		;;
	esac
	return 0
}
