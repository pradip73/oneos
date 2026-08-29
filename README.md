# OneOS

A custom Linux-based desktop operating system.

**Current state: Phase 1 (base image). There is no desktop yet.** The compositor is Phase 2 and the shell is Phase 3. See [docs/BUILD-PLAN.md](docs/BUILD-PLAN.md).

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — full technical architecture and the honest limitations
- [docs/BUILD-PLAN.md](docs/BUILD-PLAN.md) — phased plan, milestones, timeline

## Target specification

| | |
|---|---|
| **Minimum (desktop + Windows apps)** | 4 GB RAM, dual-core x86-64, 32 GB storage |
| **Recommended (with Android apps)** | 8 GB RAM — Plasma idles near 1 GB and the Waydroid container adds 1–1.5 GB on top |
| **Lite tier** | 2 GB RAM — desktop and browser only; the Windows and Android layers are **not offered** at this tier |
| Architecture | x86-64 only for now; arm64 is a post-1.0 item |

The 2 GB restriction is not a tuning problem. The Waydroid Android container alone needs 1–1.5 GB, and a Wine prefix running an app adds 200–600 MB on top of the desktop. Those layers cannot coexist with a usable session in 2 GB on any operating system.

## Building the ISO

**You cannot build this from Windows.** `debootstrap`, `live-build` and the kernel toolchain are Linux-native, and there is no cross-build path. You need a Debian-based Linux environment. In order of least to most invasive:

1. **WSL2 with Debian** — a Windows feature; it does not install an OS on your disk and leaves Windows untouched. Requires admin rights and one reboot. Fastest option.
2. **A Debian VM** under QEMU, VirtualBox or Hyper-V. Fully isolated, slower.
3. **A dedicated Linux machine.** Best long-term — from Phase 2 onward you need real GPU/DRM access to test the compositor, which neither WSL nor a VM provides properly.

Once you have one:

```bash
sudo apt update
sudo apt install -y live-build debootstrap xorriso squashfs-tools rsync
```

**Important:** copy this repository onto the Linux filesystem first (for example `~/oneos`). Building on a Windows-mounted path such as `/mnt/d/os` will fail — live-build creates device nodes and mounts inside a chroot, which drvfs cannot support. `build.sh` checks for this and stops early with a clear message.

```bash
sudo ./build.sh
```

First build takes 20–60 minutes and downloads roughly 1.5 GB of packages. Later builds reuse the apt cache and are much faster. Output lands in `out/` with a SHA256 sum.

### Disk space

The finished ISO is only ~1.5 GB, but the build keeps several uncompressed stages on disk at once:

| Stage | Size | Why |
|---|---|---|
| apt cache | ~1.2 GB | downloaded `.deb` files, still compressed |
| `chroot/` | ~2.5 GB | those packages **unpacked** into a root filesystem — a `.deb` expands to 2–3× its size |
| `binary/` + squashfs | ~2.0 GB | staging copy before it becomes an ISO |
| final ISO | ~1.5 GB | |
| **peak concurrent** | **~7–8 GB** | |

So **15 GB free is enough** for an ISO build, and `build.sh` checks for that. The ISO is small because everything inside it is squashfs+zstd compressed; the build needs the files uncompressed, and holds both forms at once.

**Building the custom kernel is a different job** and needs roughly **35 GB** with debug info and BTF enabled. Size your volume for that separately when you reach Phase 1b.

### Writing to USB

```bash
sudo dd if=out/oneos-0.1.0-amd64.hybrid.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

From Windows, use Rufus or balenaEtcher in **DD / image mode** (not ISO mode — the image is a hybrid ISO).

## What this ISO does and does not do

**Does:** boots on UEFI and legacy BIOS into a **Plasma Wayland desktop**, includes
non-free firmware so Wi-Fi works on real laptops, ships the Debian installer so it
can install onto a fresh machine, runs **Windows `.exe` files through Wine** (64-bit
and 32-bit, with DXVK-capable Vulkan drivers), carries **Waydroid for Android apps**,
and applies the OneOS kernel tunables and zram configuration.

**Does not:**

- **This is not the OneOS shell.** The desktop is KDE Plasma with OneOS branding —
  borrowed scaffolding so the OS is usable while the real compositor and shell are
  built in Phases 2–3. See `build/config/package-lists/oneos-desktop.list.chroot`.
- **Android needs one manual step.** `sudo waydroid init` downloads the ~700 MB
  Android image on first use. It is not shipped in the ISO.
- **Google Play Services do not work**, so banking apps, Netflix and anything using
  Play Integrity will refuse to run. ARCHITECTURE.md §4.3 explains why this cannot
  be fixed.
- **Wine is not sandboxed yet.** A `.exe` you download runs with your full user
  privileges and can read every file you can. The per-app prefix sandbox is Phase 4.
  Treat Windows software on this image exactly as carefully as you would on Windows.
- No atomic updates, no Secure Boot, no disk encryption by default. Later phases.

## Layout

```
build.sh                    Build orchestrator (run this)
VERSION                     Single source of truth for the version string
build/auto/config           live-build configuration
build/config/package-lists/ What goes into the image
build/config/includes.chroot/  Files overlaid onto the root filesystem
kernel/                     Custom kernel config fragment and patch series
docs/                       Architecture and build plan
out/                        Build artifacts (gitignored)
```

## Kernel

Phase 1 ships Debian's stock kernel so the ISO boots on day one. The custom kernel in `kernel/` replaces it in Phase 1b. The config fragment there is merged onto Debian's config rather than a defconfig — Debian's config already handles the hardware breadth that consumer laptops demand.

One thing to know before building it: `CONFIG_NTSYNC` requires kernel 6.14 or newer, but we target the 6.12 LTS. On 6.12 that option is a no-op unless the backport patch is applied, and the build will not warn you. Verify `/dev/ntsync` exists at runtime.
