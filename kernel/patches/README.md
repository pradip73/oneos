# Kernel patch series

Ordered patches applied on top of a pristine upstream tree by
`../build-kernel.sh`. Name them `NNNN-description.patch`.

**This is a patch series, never a fork.** A fork means inheriting the kernel's
entire security-backporting burden, which is the most common way small
distributions die. Every patch here should carry a comment at the top saying
why it exists and what would let it be dropped.

## What belongs here right now

**`CONFIG_NTSYNC` — the Wine fast path.** It was upstreamed in 6.14 and OneOS
targets the 6.12 LTS, so on 6.12 the option in `oneos.config-fragment` does
nothing at all: Kconfig does not error on symbols it has never heard of, and
`merge_config.sh` only warns. The build script checks for it explicitly and
says so, because a silently-absent performance feature is worse than a loud
one.

Two ways out, and the second is probably right:

1. Put the ntsync backport here as `0001-ntsync.patch`, and carry it until
   the next LTS.
2. Do without it. Wine falls back to its fsync path, which is slower but
   correct, and the whole question disappears when the next LTS ships with
   ntsync included.
