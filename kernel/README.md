# NovaOS kernel

Phase 1 ships Debian's stock kernel so the ISO boots on day one. This directory
builds the replacement, which lands in Phase 1b.

**Do not start here.** Get a booting ISO with the stock kernel first. A custom
kernel that fails to boot is very hard to debug when nothing else is known-good.

## Strategy

Track the upstream **LTS** kernel and carry deltas as an ordered patch series —
never a fork. A fork means inheriting the kernel's entire security-backporting
burden, which is the most common way small distributions die.

The config in [novaos.config-fragment](novaos.config-fragment) is a *fragment*,
merged onto Debian's config rather than onto `defconfig`. Debian's config already
covers the hardware breadth real consumer laptops need — Wi-Fi chipsets, webcams,
touchpads, power management. Starting from `defconfig` produces a kernel that
boots beautifully in a VM and fails on actual hardware.

## Disk and time

Roughly **35 GB** and 40–90 minutes on the 6-core/12-thread build machine, with
debug info and BTF enabled. This is far more than the ISO build needs — build it
on `C:` (173 GB free), not `D:` (~30 GB free).

## Building

```bash
sudo apt install -y build-essential fakeroot libncurses-dev bison flex \
    libssl-dev libelf-dev bc rsync dwarves debhelper
./build-kernel.sh 6.12.48
```

The resulting `.deb` packages go into `../out/kernel/`. To use them in the ISO,
replace `linux-image-amd64` in
`build/config/package-lists/novaos-base.list.chroot` with the built package and
add it to a local repo (see `docs/ARCHITECTURE.md` §6.2).

## The ntsync problem — read before building

`CONFIG_NTSYNC` gives Wine in-kernel NT synchronization primitives and is a large
performance win over the older esync/fsync approaches. **It landed upstream in
6.14, but we target the 6.12 LTS.**

On 6.12 the `CONFIG_NTSYNC=y` line in the fragment is simply ignored — Kconfig
does not error on unknown symbols, so **the build will silently produce a kernel
with no ntsync and tell you nothing**.

Two options:

1. Place the ntsync backport patch in `patches/` (see below) and apply it. This
   is what `build-kernel.sh` does if any patches are present.
2. Skip ntsync for now and accept Wine's fsync path. Perfectly workable for
   Phase 1b; revisit when the next LTS ships with ntsync included.

Either way, **verify after booting**:

```bash
ls -l /dev/ntsync          # must exist
zgrep NTSYNC /proc/config.gz
```

## Patch series

Patches live in `patches/`, applied in filename order. Name them `NNNN-description.patch`.
Keep the series small and rebase it onto each upstream point release rather than
letting it drift. Every patch needs a comment at the top saying why it exists and
what would let it be dropped.
