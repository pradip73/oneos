# Phased Build Plan

Companion to [ARCHITECTURE.md](ARCHITECTURE.md). Status: **draft for review**.

Durations assume **one full-time developer** (you), learning as you go. Halve Phases 2–5 with a second experienced developer; the shell phases parallelise best.

Guiding rule: **every phase ends with something that boots and can be demonstrated.** No phase is allowed to be pure infrastructure with nothing to show.

---

## Phase 0 — Foundations and de-risking
**Duration: 6–10 weeks · Goal: prove you can do the hard parts before committing.**

This phase exists to fail cheaply. If Phase 0 goes badly, that is valuable information at week 8 rather than month 20.

Deliverables:

1. **Hardware and lab.** One build machine (16+ cores, 64 GB RAM, 1 TB NVMe — image builds are I/O heavy), plus **two physical test laptops**: one Intel/AMD integrated graphics, one with an Nvidia dGPU. VMs will not surface the bugs that kill consumer distros. A serial console or at minimum a second machine for SSH debugging.
2. **Skills spikes**, each a throwaway:
   - A "hello triangle" Wayland client, written by hand against `libwayland`.
   - A minimal `wlroots` (or Smithay) compositor that opens a window and moves it. ~600 lines. This is the go/no-go gate for the whole project.
   - A QML app with an animated custom control.
   - Build a stock kernel with a modified `.config`, boot it on real hardware.
   - Build one Debian package from source with `debhelper` and install it.
3. **Manual integration test.** On stock Debian: install Wine, run three real Windows apps; install Waydroid, run three real Android apps. Document exactly what broke. **This calibrates your promises before you make them.**
4. **A written product definition**: target user, the ten things the OS must do flawlessly, and an explicit non-goals list.
5. **Naming, licensing decision (GPL-3.0 or MPL-2.0 for your own code), and trademark search.**

**Milestone / go-no-go:** your own compositor draws a window and responds to input on real hardware, and you have an honest written list of what Wine and Waydroid actually do on your test apps.

---

## Phase 1 — Reproducible base and build system
**Duration: 8–12 weeks · Goal: a bootable, self-built base OS with no desktop.**

Deliverables:

1. **`mkosi`-based image build** producing a bootable image from a single declarative definition, from a `mmdebstrap` Debian root.
2. **Self-hosted APT repository** with `aptly`; a local Debian mirror; GPG signing key generated and stored offline; `dev`/`beta`/`stable` channels.
3. **Custom kernel package** — LTS base, your `.config`, patch series under version control, including the ntsync backport. Built and published to your repo.
4. **Boot chain:** `systemd-boot`, `dracut` initramfs, a unified kernel image (UKI). Booting to a text console on both test laptops.
5. **CI** — self-hosted (Woodpecker CI or Forgejo Actions; Gitea/Forgejo for hosting). Every push builds the image; nightly images published.
6. **A/B partition layout defined** and `systemd-sysupdate` configured, even though there's nothing yet to update to.

**Milestone:** `git push` produces a signed, bootable ISO. Both test laptops boot it to a login prompt, with your kernel, in under 15 seconds.

**New skills required here:** Debian packaging, `dracut`, systemd unit ordering, kernel Kconfig, GPG key management. This phase is tedious rather than difficult — expect frustration, not intellectual challenge.

---

## Phase 2 — Compositor
**Duration: 16–24 weeks · Goal: a working, if plain, graphical session.**

The longest and riskiest phase. Resist adding shell features here.

Deliverables:

1. **Interaction-design prototype first** (2–3 weeks, throwaway): mock the whole desktop in QML or Figma. Decide the taskbar/launcher/notification model *before* writing compositor code. Cheap to change now, expensive later.
2. **Compositor core** on `wlroots`/Smithay:
   - DRM/KMS backend, multi-monitor with hotplug, correct scaling (integer, then fractional)
   - `libinput`: keyboard, mouse, touchpad gestures, touch
   - `xdg-shell` (windows), `wlr-layer-shell` (panels/overlays), `xdg-decoration`
   - Xwayland hosting — non-negotiable, Wine depends on it
   - Session lock protocol, idle inhibit, screencopy
   - `systemd-logind` integration: VT switching, seats, suspend/resume
3. **Window management:** floating windows with the standard interaction model your users expect — move, resize, snap to edges, minimise/maximise, alt-tab, workspaces.
4. **Rendering:** damage tracking, vsync, and a hard 60 fps target under load. Animation infrastructure for open/close/minimise.
5. **Crash resilience:** the compositor crashing must not lose the user's session more than it has to. Watchdog and automatic restart.

**Milestone:** boot to a graphical session, launch `firefox` and a terminal from a TTY, move/resize/snap windows, plug in a second monitor and have it work, suspend and resume without corruption. On both laptops.

**Honest note:** this is where the project most commonly stalls. Nvidia hybrid graphics and suspend/resume will each cost you weeks. Multi-monitor hotplug is harder than it looks.

---

## Phase 3 — The shell
**Duration: 20–28 weeks · Goal: the product actually becomes a desktop.**

Deliverables:

1. **A design system in QML** — tokens (colour, type, spacing, motion), a component library, light and dark themes. Build this before the features; it's what makes the result look intentional rather than assembled.
2. **Shell surfaces:** taskbar with window list; launcher with unified search (apps, files, settings, calculator); notification centre; system tray (`StatusNotifierItem`); quick-settings panel (Wi-Fi, Bluetooth, volume, brightness, night light); lock screen; logout/shutdown; on-screen keyboard.
3. **Settings app** — one coherent app: display, audio, network, Bluetooth, printers, users, power, updates, keyboard/region, accessibility, default apps, about. **Budget 8+ weeks for this alone**; it is consistently underestimated.
4. **Portal backends** (`xdg-desktop-portal-<yourshell>`): file chooser, screenshot, screencast, settings, notifications, inhibit. Required for Flatpak apps to function correctly.
5. **Flatpak integration** plus a software centre front-end (consider AppStream metadata; consider reusing GNOME Software's backend logic rather than writing a package resolver).
6. **First-run setup wizard.**
7. **Core apps:** file manager, terminal, text editor, image viewer, screenshot tool, archive manager. Reuse existing apps where sensible; write only the file manager and terminal, which are the ones users notice.
8. **Accessibility:** AT-SPI exposure, Orca working, text scaling, high contrast, keyboard navigation throughout.
9. **Localisation infrastructure** from day one — retrofitting i18n is miserable.

**Milestone:** a non-technical person can be handed a laptop, complete setup, connect to Wi-Fi, install an app from the software centre, browse the web, change their wallpaper and find the volume control — without help and without a terminal.

**This milestone is the real product.** Everything after it is additive.

---

## Phase 4 — Windows compatibility layer
**Duration: 12–16 weeks · Goal: `.exe` files are first-class.**

Deliverables:

1. **Wine, DXVK, vkd3d-proton, wine-mono packaged** into your repo as versioned, side-by-side runtimes.
2. **Prefix manager daemon** — per-app prefixes, runtime pinning, lifecycle, cleanup on uninstall. D-Bus API for the shell.
3. **The `bubblewrap` sandbox layer** for every prefix, with portal-mediated file access. Per §3.4 of the architecture doc this is mandatory, not optional. Do it now, not later.
4. **Install UX:** double-click `.exe` → trust prompt → branded install flow → prefix created → shortcuts detected → `.desktop` entry with real icon. Uninstall must remove the prefix cleanly.
5. **Compatibility database**, seeded from Wine AppDB, with per-app overrides and a working/partial/broken rating surfaced in the UI.
6. **Diagnostics:** a log viewer and a "this app didn't work" report flow. Users will hit failures; make the failures legible.
7. **A tested app list**: pick 30 real applications across categories, verify each, publish the results honestly including the failures.

**Milestone:** install and run 25 of your 30 target apps from a double-click, sandboxed, with correct icons and windows, with no terminal involved.

---

## Phase 5 — Android compatibility layer
**Duration: 8–12 weeks · Goal: APKs are first-class.**

Deliverables:

1. **Waydroid packaged and integrated**, container hidden, lazy start and idle shutdown.
2. **Multi-window mode** — Android apps as real windows in your compositor, correctly scaled.
3. **APK install UX** mirroring the Windows flow; `.desktop` entries with real icons.
4. **Bridges:** clipboard, Downloads folder, notifications, audio in/out via PipeWire.
5. **FEX-Emu integration** for ARM-only apps, with clear UI signalling that such apps will be slower.
6. **microG evaluation and integration decision**, plus **clear, honest in-product messaging** about Play Services, Play Integrity, and banking/streaming apps. Do not let users discover this as a surprise.
7. **A tested app list**, as in Phase 4.

**Milestone:** install an APK by double-click, run it in a normal window alongside desktop apps, copy text between an Android app and a Linux app.

---

## Phase 6 — Updates, security, and trust
**Duration: 10–14 weeks · Goal: safe to give to someone who isn't you.**

Deliverables:

1. **A/B atomic updates working end to end**, with delta updates, background staging, boot-count rollback, and a tested "corrupt the new slot and confirm it recovers" scenario.
2. **Secure Boot chain**: signed shim (start the Microsoft shim-review submission at the *beginning* of this phase — it takes months), signed `systemd-boot`, signed UKI, `dm-verity` root.
3. **LUKS2 full-disk encryption by default**, TPM2-sealed, with recovery-key flow in the installer and setup wizard.
4. **Kernel lockdown + module signing** enabled.
5. **AppArmor profiles** for network-facing services.
6. **Security process**: published disclosure policy, CVE monitoring for kernel/Debian/Wine/Mesa/Waydroid, a documented patch-and-ship SLA, and at least one rehearsed emergency update.
7. **`fwupd`/LVFS** integrated and surfaced in Settings.

**Milestone:** a machine that boots with Secure Boot enabled and an encrypted disk, takes an over-the-air update, survives a deliberately corrupted update by rolling back, and applies a firmware update from Settings.

---

## Phase 7 — Installer, hardening, beta
**Duration: 12–16 weeks · Goal: 1.0.**

Deliverables:

1. **Branded Calamares installer**, tested against: UEFI and legacy BIOS, empty disk, dual-boot alongside Windows, NVMe and SATA, Intel/AMD/Nvidia graphics. **Data-loss bugs here are unforgivable; test destructively and repeatedly.**
2. **Certified hardware list** — 5–10 specific laptop models verified end to end: Wi-Fi, Bluetooth, suspend/resume, brightness keys, webcam, audio, external display, battery reporting, fingerprint reader where present.
3. **Performance pass:** boot time, memory at idle (target under 1 GB without the Android container), animation smoothness on integrated graphics, thermals.
4. **Crash reporting and diagnostics** — opt-in, self-hosted.
5. **Documentation:** user guide, troubleshooting, and a full "known limitations" page that says plainly what Wine and Android will and won't do.
6. **Closed beta (~50 users), then public beta.** Recruit non-technical testers deliberately; developers won't find the bugs that matter.
7. **Support infrastructure:** forum or Matrix, issue tracker, a triage routine you can actually sustain.

**Milestone: 1.0.** A non-technical user installs from USB onto a certified laptop, uses it as a daily driver for a week, and runs Windows and Android apps, without needing help.

---

## Phase 8+ — After 1.0

Candidates, roughly in value order: your own installer; self-built LineageOS images; ARM64 port; Wine Wayland driver by default; a store/curation program; enterprise management; tablet/touch mode; your own Flatpak build service. **Not** macOS compatibility — see §5 of the architecture doc.

---

## Summary timeline

| Phase | Duration | Cumulative | Ships |
|---|---|---|---|
| 0 — Foundations | 6–10 wk | ~2 mo | Spikes, go/no-go |
| 1 — Base + build system | 8–12 wk | ~5 mo | Bootable console image |
| 2 — Compositor | 16–24 wk | ~10 mo | Graphical session |
| 3 — Shell | 20–28 wk | ~16 mo | **A usable desktop** |
| 4 — Windows layer | 12–16 wk | ~20 mo | `.exe` support |
| 5 — Android layer | 8–12 wk | ~22 mo | `.apk` support |
| 6 — Updates + security | 10–14 wk | ~25 mo | Trustworthy system |
| 7 — Installer + beta | 12–16 wk | **~29 mo** | **1.0** |

Roughly **29 months solo, full-time**, with no allowance for illness, burnout or a bad month on Nvidia drivers. Add 20–30% contingency and call it **~3 years**; **18–24 months** with 3–4 people.

---

## Three decisions I need from you before Phase 0

1. **Rust + Smithay, or C + wlroots** for the compositor? (My recommendation: Rust, given your C# background and the security stakes.)
2. **Is dropping macOS compatibility accepted**, per §5?
3. **Solo or team?** It changes the plan materially, and it's better decided now than at month 12.
