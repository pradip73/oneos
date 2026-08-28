# How to get your ISO

You do not want to install anything on this machine. That's fine — **Route A below
needs nothing installed locally and no reboot.**

But one fact cannot be worked around: **an ISO cannot be built on Windows.**
`debootstrap`, `live-build` and the kernel toolchain are Linux-only and there is no
cross-build path. So the build has to happen on *some* Linux machine — it just
doesn't have to be yours.

---

## Route A — build in the cloud (recommended, nothing installed locally)

A cloud runner builds the ISO and hands you a download link. Your machine stays
exactly as it is.

1. Create a repository on GitHub (free; a private repo is fine).

2. Push this folder to it:

   ```bash
   git init
   git add -A
   git commit -m "OneOS Phase 1 base"
   git branch -M main
   git remote add origin https://github.com/<your-username>/oneos.git
   git push -u origin main
   ```

3. The build starts automatically. Watch it in the repo's **Actions** tab
   (~25–40 minutes).

4. When it finishes, open the run and download the
   **`oneos-0.1.0-amd64-iso`** artifact from the Artifacts section.

5. Unzip it, then write the `.iso` to a USB stick with **Rufus** or
   **balenaEtcher** in **DD / image mode** — not ISO mode, this is a hybrid image.

6. Boot the target machine from that USB.

The workflow is [.github/workflows/build-iso.yml](.github/workflows/build-iso.yml).
It also runs on self-hosted Forgejo or Gitea with only the `runs-on` label changed,
if you'd rather not depend on GitHub long term.

**Caveat worth knowing:** GitHub Actions is a third-party service, which sits
against your "self-hosted, open toolchain" preference from the brief. For a Phase 1
base image with no secrets in it, that trade is reasonable. Revisit it before you
ship signed production images — those must be built somewhere you control, because
whoever builds your images can put anything in them.

---

## Route B — build locally in WSL2 (needs one reboot)

Already 90% done. WSL2 core is installed and Virtual Machine Platform is enabled;
only the reboot is outstanding.

WSL2 does **not** install an OS on your disk. It's a Windows feature running a Linux
userland in a lightweight VM — no partitioning, and Windows is untouched. But it
does need one restart.

If you change your mind:

1. Restart Windows.
2. Run:

   ```
   powershell -ExecutionPolicy Bypass -File .\setup.ps1
   ```

That script does everything: installs Debian, installs dependencies, copies the repo
onto the Linux filesystem, builds the ISO, and drops it in `C:\oneos-out\`.

---

## Route C — a spare machine or a VPS

Any Debian or Ubuntu machine works:

```bash
git clone <your-repo> && cd oneos
bash ./bootstrap.sh
```

A €5/month VPS builds this comfortably.

---

## What you will actually get

Phase 1 base image. It:

- boots on UEFI and legacy BIOS
- reaches a **text login** — user `nova`
- includes non-free firmware so Wi-Fi works on real laptops
- carries the Debian installer, so it installs onto a fresh machine
- applies the OneOS kernel tunables and zram configuration

It does **not** have a graphical desktop. That is Phase 2 (compositor) and Phase 3
(shell) — several months of work each, per [docs/BUILD-PLAN.md](docs/BUILD-PLAN.md).
When you boot the target machine and see a black screen with a login prompt, nothing
has gone wrong. That is the Phase 1 milestone.
