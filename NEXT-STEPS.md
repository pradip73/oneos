# Where the project stands

Last updated at the end of the first build-and-test session.

## What OneOS is right now

**Version 0.2** — a working Debian-based desktop OS with Windows and Android
compatibility layers, built entirely in GitHub Actions. It boots, reaches a
Plasma desktop, and carries OneOS branding.

**The ISO to use is the newest successful run:**
https://github.com/pradip73/oneos/actions → open the top green run → Artifacts →
`oneos-0.2.0-amd64-iso` (~2.7 GB)

## Verified working in a VM

- Boots on UEFI
- Kernel, graphics stack and SDDM start
- **Plasma desktop reaches the user** (this took six failed builds to achieve)
- Debian text installer runs
- NetworkManager connects

## Fixed but NOT yet tested

Everything below is written and built but has never been run. This is the list
to work through first:

- [ ] DNS resolution (`ping debian.org` from a terminal)
- [ ] Boot splash — the teal screen with the OneOS mark
- [ ] Wallpaper, accent colour and login-screen branding
- [ ] Desktop icon reads **Install OneOS**, not Install Debian
- [ ] Bengali text renders as letters, not boxes
- [ ] Double-click a `.deb` → installs
- [ ] Double-click an `.exe` → trust prompt → runs
- [ ] Double-click an `.apk` → offers the one-time Android setup
- [ ] Installed programs appear on the desktop by themselves
- [ ] **Calamares actually installs to disk** — never once run; test in a VM only

## The plan, in order

1. **Verify the list above.** Everything after this is built on guesses until
   it is done.
2. **Sandbox Wine.** Right now a downloaded `.exe` has full access to the user's
   files. `docs/ARCHITECTURE.md` §3.4 calls this mandatory and it is still owed.
   Do not put this OS in anyone else's hands before it is fixed.
3. **Test on real hardware.** Wi-Fi, suspend/resume, battery, brightness keys,
   and Waydroid — none of which a VM can tell you anything about.
4. **0.3:** own welcome app, Waydroid working, 4 GB machine test.
5. **Own foundations:** custom kernel (Phase 1b), own APT repo, A/B updates.
6. **The real OneOS:** Phase 2 compositor, Phase 3 shell — 8–12 months. Plasma
   is deleted at that point.

## Designs

- Desktop, glass, Control Panel, This computer:
  https://claude.ai/code/artifact/621b35a8-165c-486e-a850-f486a7c37721
- Logo, boot splash, installer:
  https://claude.ai/code/artifact/a788ae82-a516-4627-b957-c19624dd87e8

## Testing in VirtualBox — settings that matter

| | |
|---|---|
| RAM | 4096 MB tests the real minimum spec; more is fine for feature testing |
| Video memory | **128 MB** — less than this and the desktop will not start |
| Session | Pick **Plasma (X11)** at the login screen; VirtualBox handles Wayland poorly |
| EFI | Enable it |

Android will not work in a VM at all, and Wine's GPU acceleration will not
either. Both need real hardware.

## Things that are true and easy to forget

- **This is not the OneOS shell.** The desktop is KDE Plasma wearing OneOS
  colours. The real one is Phase 2–3.
- **Android needs `sudo waydroid init` once** — a ~700 MB download.
- **Google Play does not work**, so banking apps and Netflix will refuse to run.
  This cannot be fixed; see `docs/ARCHITECTURE.md` §4.3.
- **Wine is not sandboxed yet.** Treat `.exe` files exactly as carefully as on
  Windows.

## Lessons from the failures, so they are not repeated

- `--apt-recommends false` silently dropped `user-setup`, so the live user was
  never created. The build was green and the ISO was unusable.
- Packages that work on an installed system can break a live ISO: `dracut`
  conflicts with `live-boot`, and `systemd-boot`'s postinst needs a real ESP.
- Ubuntu's `live-build` is a fork of Debian's with different option names. The
  build runs in a Debian container for that reason.
- Plymouth's script module cannot draw a rectangle; every shape must be a PNG.
