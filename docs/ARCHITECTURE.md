# Technical Architecture — Custom Linux-Based Desktop OS

Status: **scoping draft for review**. No implementation until signed off.
Working codename used throughout: **NovaOS** (placeholder — rename before Phase 1).

---

## 0. Executive summary

You are building four separable products that happen to ship as one ISO:

| # | Product | Difficulty | Who has done it |
|---|---------|-----------|-----------------|
| A | A Linux distribution (base, packaging, updates, installer) | Medium. Well-trodden. | Hundreds of distros |
| B | An original desktop shell + Wayland compositor | **Hard.** The real work. | ~8 teams worldwide (GNOME, KDE, COSMIC, Enlightenment, Cinnamon, elementary, Deepin) |
| C | Windows app compatibility | Medium *if integrating*, impossible if reimplementing | Valve (Proton), CodeWeavers, Bottles |
| D | Android app compatibility | Medium-low. Mostly plumbing. | Waydroid project |

**A, C and D are integration work.** B is genuine original engineering and will consume ~60% of total effort. Plan accordingly: the shell is both the differentiator and the risk.

Realistic timeline to a 1.0 that a non-technical person could daily-drive:

- Solo, part-time: not achievable. Solo, full-time: **30–42 months**.
- 3–4 experienced people full-time: **18–24 months**.

I'd rather say that up front than have you discover it at month 14.

---

## 1. Base distribution and kernel

### 1.1 Do not build from scratch (LFS / Yocto)

Ruled out: Linux From Scratch and Yocto/Buildroot. You would own bootstrapping ~2,000 packages, CVE triage for all of them, and a toolchain. That is a full-time job for a team of ten, permanently, and it is *not* where your product differentiation lives. Yocto is right for embedded appliances with fixed hardware; it is wrong for a general-purpose desktop that must boot on arbitrary consumer laptops.

"Full ownership of the codebase" is satisfied by owning the *shell, the integration layer, the build system, the repository, and the signing keys*. It does not require owning `glibc`.

### 1.2 Recommendation: Debian stable as the base, consumed as a package pool

**Choice: Debian (current stable), with your own APT repository layered on top, and a self-built kernel.**

Why Debian:

- **Packaging tooling is the best-documented and most scriptable** (`dpkg`, `apt`, `debhelper`, `sbuild`, `aptly`). You will write a lot of packaging; this matters more than it sounds.
- **Reproducible builds** are furthest along in Debian, which underpins a security story you can actually defend.
- **No corporate owner.** No CLA, no rug-pull risk, no trademark negotiation. Aligns with your no-proprietary-dependency constraint.
- **`debootstrap`/`mmdebstrap` give you a deterministic, scriptable root filesystem** in one command, which keeps your image pipeline simple.
- A stable ABI for ~2 years per release means your shell isn't chasing moving targets while you're trying to write it.

Why not the alternatives:

- **Arch** — newest Mesa/Wine/kernel (genuinely helpful for the Windows and Android layers), but rolling release means the OS breaks under you at random, and `archiso` + AUR is not a foundation for a product with non-technical users. Reconsider only if gaming/Proton parity becomes the headline feature.
- **Fedora** — excellent technology (OSTree, systemd-first, Wayland-first) but 13-month lifecycles force a treadmill, and Red Hat governance is a dependency you said you want to avoid.
- **Ubuntu** — Canonical CLA, Snap mandates, trademark restrictions on derivatives. Direct conflict with your goals.

**Honest tradeoff:** Debian stable ships older Mesa and Wine than you want. Mitigation, in order: (1) build Mesa, Wine and the kernel yourself into your own repo — you should do this anyway; (2) selectively pull from `backports`. Do *not* mix in `testing`/`sid` broadly; that gives you Arch's instability without Arch's benefits.

### 1.3 Kernel strategy

**Track upstream LTS. Do not fork.**

- Base on the current **LTS kernel** (6.12.x line at time of writing), tracking point releases for CVE fixes.
- Maintain your deltas as an ordered **patch series** (a git branch rebased onto upstream, or `quilt`), never as a divergent fork. A fork means inheriting the kernel's entire security-backporting burden. That is the most common way small distros die.
- Ship your own `.config`, derived from Debian's config as the starting point — it already covers the hardware breadth of consumer laptops — then trimmed.

Config requirements driven by your features:

**For Waydroid (Android):**

- `CONFIG_ANDROID_BINDER_IPC`, `CONFIG_ANDROID_BINDERFS`. Binderfs is upstream; you do **not** need out-of-tree `anbox-modules` on a modern kernel.
- `CONFIG_ASHMEM` is obsolete — current Waydroid uses memfd. Verify against the exact Waydroid version you pin.
- User namespaces (`CONFIG_USER_NS`), full cgroup v2, `CONFIG_MEMCG`.

**For Wine/Proton (Windows):**

- `CONFIG_NTSYNC` — the in-kernel NT synchronization driver (upstreamed in 6.14). A large, measurable win over the older esync/fsync hacks. **It requires ≥6.14, which is newer than the 6.12 LTS.** Decision point: ship 6.12 LTS plus a backported ntsync patch, or track a newer stable line. My recommendation: **6.12 LTS + ntsync backport in your patch series** through Phase 4, then move to the next LTS once it carries ntsync natively.
- `futex_waitv` (present since 5.16). Also `vm.max_map_count` ≥ 1048576 and a high `fs.file-max` — set via sysctl, not Kconfig.

**General desktop:**

- `CONFIG_PSI` (pressure stall information — needed for a responsive low-memory story).
- `CONFIG_ZRAM` with zstd; enable zram swap by default. Meaningful on the 8 GB laptops your target audience owns.
- `CONFIG_FUSE_FS` (Flatpak, AppImage, portals).
- AppArmor as the default LSM — Debian's default, and a simpler policy language than SELinux for this scope.
- `CONFIG_MODULE_SIG_FORCE` with your signing key, and kernel `lockdown` in integrity mode once Secure Boot lands (Phase 6).
- Keep `CONFIG_DEBUG_INFO_BTF` **on** — you want BTF for eBPF-based diagnostics later.

**Where you'll need to learn:** Kconfig semantics, `make menuconfig`, initramfs generation (prefer `dracut` over `initramfs-tools` — better documented, systemd-friendly), module signing, and reading `dmesg` fluently. Budget 3–4 weeks of focused study. You do *not* need to write kernel C code for v1, and you should actively resist doing so.

---

## 2. Desktop environment — the core of the product

### 2.1 Architectural shape

Modern Linux desktops are **Wayland compositors**. X11 is maintenance-only upstream; starting a new X11 desktop in 2026 means building on a foundation being actively removed. Wayland is the only defensible choice.

A Wayland desktop is three layers:

```
+------------------------------------------------------+
|  Shell UI: panel, launcher, notifications, settings,  |  <- your design lives here
|  lock screen, overview, on-screen keyboard            |
+------------------------------------------------------+
|  Compositor: window management, input routing,        |  <- the hard, invisible part
|  output/monitor mgmt, protocol implementations,       |
|  Xwayland hosting, damage tracking, rendering         |
+------------------------------------------------------+
|  System plumbing: DRM/KMS, libinput, Mesa/EGL,        |  <- use as-is, do not touch
|  systemd-logind, PipeWire, portals, PolicyKit         |
+------------------------------------------------------+
```

### 2.2 Recommendation: Qt 6 / QML shell on a `wlroots`-backed compositor

Concretely: **compositor core in Rust or C against `wlroots`; shell UI in QML.**

Two credible variants, and I'll name my pick:

**Option 1 (recommended): `wlroots` compositor + Qt/QML shell as a privileged client.**

- The compositor is a small binary built on `wlroots` — the library behind Sway, Hyprland and Wayfire. It gives you roughly 80% of a compositor for free: DRM backend, libinput integration, damage tracking, Xwayland management, and correct implementations of ~40 Wayland protocols. This is the single biggest lever on your timeline.
- The shell (panel, launcher, notification centre, settings) is a Qt 6/QML application talking to the compositor over **private Wayland protocols you define**, plus the standard `wlr-layer-shell` for panels and overlays.
- **Why QML for you specifically:** it is declarative, reactive, property-binding-driven, with a component model and hot reload. It is the closest thing in the native world to your Angular experience — you'll be productive in days, not months. It also has a genuinely good GPU-accelerated scene graph and animation system, which is what "polished" means in practice.
- Licensing: Qt 6 under LGPLv3 is fine for an open-source OS, provided you link dynamically and preserve relink-ability. Trivial for a distro.

**Option 2: `QtWaylandCompositor` — compositor *and* shell in one QML codebase.**

- Genuinely elegant, and the fastest possible prototype.
- **Why not for production:** you inherit responsibility for every Wayland protocol yourself — fractional scaling, presentation-time, tearing control, session lock, screencopy, DRM leasing, colour management. `wlroots` has these; QtWaylandCompositor largely does not. You would spend year two reimplementing `wlroots`.
- **Do use it in Phase 2 as a throwaway prototype** to validate interaction design cheaply, then rebuild on `wlroots`. That is a good use of it.

**Option 3: Flutter shell over a wlroots compositor.** Excellent designer velocity and animation, and Canonical proved the Linux embedder is viable (Ubuntu's installer). But Dart plus the Flutter engine is a heavy runtime governed by Google, embedder/compositor integration is less trodden, and it pulls you out of the C/C++ ecosystem the rest of your stack lives in. Conflicts with "minimal external dependencies."

**Option 4: GTK4 + libadwaita.** Ruled out. libadwaita is GNOME's design language with deliberately limited theming; fighting it to look distinctive is a losing battle, and GTK's API churn is a real maintenance tax.

**Rejected outright: theming an existing DE.** You said this and you're right. A themed KDE is a themed KDE; users recognise it, and you inherit KDE's settings complexity — the opposite of "approachable as Windows."

### 2.3 Language choice for the compositor

`wlroots` is a C library. Two paths:

- **C** — direct, zero friction, matches every example and the whole `wlroots` ecosystem. Downside: you will write memory-safety bugs in the most security-sensitive process on the system.
- **Rust, via the `smithay` ecosystem or Rust bindings to `wlroots`** — System76's COSMIC is built on Smithay and is a real shipping proof point. Memory safety in the process handling all input and all window content is worth a great deal. Binding churn is the cost.

**Recommendation: Rust + Smithay** if you're willing to learn Rust — and you should; it is a far kinder first systems language than C for someone coming from C#. **C + wlroots** if you want the shortest path to the most copyable examples. Either is defensible. Do not use C++ here.

Calibration for your background: this is the steepest learning curve in the project. Wayland's protocol model, buffer lifetimes, DRM/KMS modesetting and input-grab semantics have no analogue in web development. Budget **3–4 months** to become genuinely competent, and expect to throw away the first compositor you write.

### 2.4 What "user-friendly as Windows" concretely requires

A product requirement, but it constrains architecture. Minimum shipping surface for a non-technical user:

- Taskbar with window list, system tray (`StatusNotifierItem` — the live tray protocol, not the dead XEmbed one), clock/calendar.
- Start-menu-equivalent launcher with search across apps, files and settings.
- Notification centre implementing `org.freedesktop.Notifications`.
- **One single, complete Settings app** — not a launcher for twelve tools. A large sub-project on its own: display/multi-monitor, audio (PipeWire), network (NetworkManager), Bluetooth, printers (CUPS), users, power, Wi-Fi, updates, keyboard/region, accessibility, default apps.
- File manager, terminal, text editor, image viewer, screenshot tool, archive manager, media player, PDF viewer.
- Installer, first-run setup wizard, and a recovery path.
- Accessibility: screen reader (Orca + AT-SPI), high contrast, text scaling. Not optional — a legal requirement in several markets and a brutal retrofit.
- Fractional scaling that actually works on HiDPI laptops.

Reuse aggressively wherever it isn't user-visible differentiation: NetworkManager, PipeWire/WirePlumber, CUPS, BlueZ, `xdg-desktop-portal`, PolicyKit, `systemd-logind`, and `fwupd` (firmware updates — genuinely important on consumer hardware). Write only the front-ends.

---

## 3. Windows application compatibility

### 3.1 Strategy: integrate Wine, contribute upstream, never hard-fork

```
.exe / .msi
   |
Per-app Wine prefix (isolated WINEPREFIX per application)
   |
Wine 10.x  --  wine-mono (.NET Framework)  --  wine-gecko
   |
DXVK (D3D9/10/11 -> Vulkan)  ·  vkd3d-proton (D3D12 -> Vulkan)
   |
ntsync (kernel NT sync primitives)  ·  Vulkan / Mesa
```

Do not reimplement any of this, and do not fork Wine. Track upstream releases; carry integration patches only, and upstream them where you can.

### 3.2 Two viable bases

- **Upstream Wine (optionally plus `wine-staging`)** — cleanest, best licence hygiene (LGPL 2.1+), you follow releases directly. Recommended.
- **Proton (Valve)** — Wine + DXVK + vkd3d-proton + patches, pre-integrated and battle-tested against thousands of games. Open source, but built around Steam's runtime container and assumes Steam. Excellent to *study* and to take patches from; awkward as a base for a general-purpose desktop.

**Recommendation: upstream Wine + DXVK + vkd3d-proton, assembled by you into your own runtime**, using Proton's patch set as a reference. Build these into your own APT repo so you control versions independently of Debian.

### 3.3 Integration design

The hard part isn't running Wine. It's making it feel like the OS runs Windows apps, rather than like the user is administering Wine.

1. **A prefix manager daemon.** One `WINEPREFIX` per installed application, never one global prefix — global prefixes are how Wine setups rot, because one app's DLL override breaks another. Bottles proved per-app isolation is right. Store under `~/.local/share/<os>/prefixes/<app-id>/`.
2. **Runtime versioning.** Ship multiple Wine runtimes side by side and pin each installed app to the runtime it was verified against. Upgrading Wine must never silently break an installed app.
3. **Install flow.** Double-click `.exe` → *your* installer UI appears (not raw Wine) → it creates a prefix, runs the installer inside it, detects created shortcuts, and registers a proper `.desktop` entry with an extracted icon. The user should never type `wine`.
4. **Windowing.** Wine's native Wayland driver has matured, but Xwayland is the safer path for v1. Plan: **Xwayland by default, Wayland driver behind a flag, re-evaluate at Phase 7.** Never use Wine's virtual-desktop mode by default — Windows apps must be real, first-class windows in your compositor.
5. **Filesystem mapping.** Map `C:\` inside the prefix and `Z:\` to `/`; map the user's Documents/Downloads/Pictures onto the Windows equivalents so file dialogs land somewhere sensible.
6. **Do NOT register `binfmt_misc` for `.exe` by default.** It turns any downloaded `.exe` plus a stray `chmod` into a one-click malware event. Route through your desktop-file handler with an explicit trust prompt instead.
7. **A compatibility database.** Per app: known-good runtime version, required DLL overrides, required winetricks verbs, and a working/partial/broken rating. Seed from public Wine AppDB data, then maintain your own. This is what makes the experience feel curated rather than random.

### 3.4 Honest limitations — read this section twice

These are not bugs you can fix. They are structural.

| Will not work | Why |
|---|---|
| **Kernel-mode anti-cheat** (Easy Anti-Cheat, BattlEye in kernel mode, Vanguard, nProtect) | Requires a Windows kernel driver. Vanguard is unfixable by design. EAC and BattlEye have Proton-compatible modes, but **the game developer must opt in** — you cannot enable it. |
| **Any Windows kernel driver** | Antivirus, VPN clients with kernel filters, virtual disk/CD drivers, hardware vendor utilities, many printer/scanner drivers, most peripheral configuration tools (RGB, DAC, gaming mice). |
| **DRM-heavy media** (PlayReady, some Widevine paths) | Requires an OS/hardware trust chain that does not exist under Wine. |
| **Hyper-V, WSL, Windows containers, HAXM** | Windows hypervisor internals. |
| **Active Directory integration, Group Policy, some WMI paths** | Deep OS integration Wine does not model. |

| Will work partially | Reality |
|---|---|
| **Microsoft Office** | 2016 and earlier are broadly workable; 2019/2021/365 range from awkward to broken, and Microsoft actively breaks Wine paths. **Do not put "runs Office" on your website.** Default to web Office or LibreOffice. |
| **Adobe Creative Cloud** | The CC desktop app is the blocker. Photoshop up to roughly CS6/CC2014 works; anything recent does not. |
| **.NET** | .NET Framework via wine-mono covers a large share of line-of-business apps. For modern .NET 6+ apps it is often better to run the *native Linux* .NET runtime and skip Wine entirely — you have exactly the background to exploit this. WPF is the weak spot; WinForms is more reliable. |
| **Games** | Broadly excellent; Proton proved this. The failure mode is anti-cheat, not rendering. |
| **WinUI 3 / Windows App SDK** | Immature Wine support. Expect breakage. |
| **Printing and scanning from Windows apps** | Basic CUPS bridging works; vendor-specific drivers do not. |

**Performance:** CPU-bound work runs at near-native speed — Wine translates API calls, it does not emulate the CPU. GPU work through DXVK is typically 0.85–1.0× native Windows, occasionally faster. **First-run shader compilation stutter is the main perceptible cost**; mitigate with a shader cache. Per-prefix memory overhead is modest but non-zero, which matters if a user installs twenty Windows apps.

**Security — the most important paragraph in this document:** **Wine is not a security boundary.** The Wine project says so explicitly. A malicious `.exe` runs with the user's full privileges and can read every file the user can. You are inviting the Windows malware ecosystem onto a desktop aimed at non-technical people. This must be architected for, not disclaimed in a EULA. Mitigation, and I consider this **mandatory, not optional**: run every Wine prefix inside a `bubblewrap` sandbox with an explicit filesystem allowlist and portal-mediated file access — the same model Flatpak uses. Budget real time for it in Phase 4; retrofitting is far harder.

---

## 4. Android application compatibility

### 4.1 Strategy: Waydroid

**Waydroid** runs a full LineageOS system image in an LXC container against the host kernel, compositing Android's output into your Wayland session. It is the only mature option; Anbox is effectively superseded.

Requirements it imposes:

- Kernel binder (`CONFIG_ANDROID_BINDERFS`) — covered in §1.3.
- A Wayland compositor (you have one) with `wl_shm` and GBM/DMA-BUF buffer sharing.
- Mesa on the host; the container uses the host GPU via `/dev/dri` passthrough.
- LXC and Python 3 on the host.

### 4.2 Integration design

1. **Hide the container.** The Waydroid session should start lazily on first Android app launch and shut down after idle. Never expose "start Waydroid" to the user.
2. **Multi-window mode**, not the full-screen Android desktop. Each Android app should be a real window in your compositor. Waydroid supports this; it needs correct plumbing.
3. **`.apk` handling.** Double-click an APK → your UI installs it → a `.desktop` entry appears with the app's real icon and name. Waydroid already exports `.desktop` files; wrap and polish that.
4. **Bidirectional integration:** shared clipboard, shared Downloads folder, notification bridging into your notification centre, and correct DPI/scaling so Android apps aren't tiny or blurry.
5. **Image provenance.** Waydroid's official images are prebuilt. True ownership means building your own LineageOS GSI — a large sub-project (AOSP builds need ~400 GB of disk and hours of CPU). **Recommendation: use official Waydroid images for v1, treat self-built images as Phase 8+.** Be honest with yourself that this is an external dependency you are accepting.

### 4.3 Honest limitations

| Issue | Reality |
|---|---|
| **ARM-only apps** | Most Play Store apps ship ARM-only. On an x86-64 host you need a translation layer. The proprietary options (Intel libhoudini, ndk-translation) **cannot legally be redistributed in your OS** — a real licensing wall. The open path is **FEX-Emu** (ARM→x86 userspace translation), which works but is slower and less complete. Expect a meaningful subset of apps not to run at all, and performance complaints on those that do. |
| **Google Play Services** | Not shippable. GApps requires a Google licence you will not get. Options: **microG** (open reimplementation; works for many apps, breaks others), or have the user side-load GApps themselves (legally grey, and you cannot ship it). Waydroid additionally requires Google device registration to pass certification. **This is the single largest practical limitation of Android-on-Linux, and your messaging should be planned around it.** |
| **Play Integrity / SafetyNet** | Fails. **Banking apps, payment apps, Netflix, most DRM video and many enterprise apps will refuse to run.** There is no legitimate fix. |
| **Hardware** | Camera passthrough is fragile. GPS, telephony, SMS, NFC, fingerprint: absent unless bridged. Microphone/audio via PipeWire works with effort. |
| **Widevine** | L3 at best. No HD streaming. |
| **Performance** | Native x86 Android apps run near-native; container overhead is small. ARM apps under FEX: expect roughly 0.3–0.6× with heavy CPU use. A running Android container costs ~1–1.5 GB RAM. |
| **GPU** | Needs Mesa in the container matching the host driver. Nvidia proprietary is the perennial problem case. |

---

## 5. macOS application compatibility — recommendation: **drop it**

You flagged this as aspirational. My advice is stronger than "defer": **remove it from the roadmap and don't mention it publicly.**

- **There is no Wine for macOS.** Darling is the only project, and despite years of work it does not run mainstream GUI applications. Wine succeeds because Win32 is a stable, documented, exhaustively reverse-engineered API with a thirty-year fixed surface. macOS is the opposite: Cocoa/AppKit/SwiftUI/Metal/CoreAnimation are enormous, insufficiently documented, and change materially every year. Reimplementing AppKit is a larger project than Wine, aimed at a moving target.
- **Code signing and notarization.** Modern macOS apps are signed, and many verify their own signature and refuse to run in a modified environment.
- **Apple Silicon.** New Mac software is increasingly arm64-only. On x86-64 hardware you'd need CPU emulation *on top of* the API reimplementation.
- **Legal.** Apple's frameworks and system libraries cannot be redistributed. Even a technically working solution would require the user to own a Mac and extract files from it — which kills it as a consumer feature.
- **Cost/benefit.** The macOS catalogue not already available on Linux or the web is small, and mostly creative-professional tools needing flawless GPU and colour management — the hardest possible case.

If a user needs a Mac app, the honest answer is a Mac or a VM. Spend that budget on the shell; it produces far more user value per month.

---

## 6. Packaging and application distribution

### 6.1 Three tiers — keep them strictly separate

| Tier | Contents | Format | Updated how |
|---|---|---|---|
| **Base OS** | kernel, systemd, Mesa, compositor, shell, settings, core apps | Your APT repo, composed into a versioned system image | Atomic A/B image update |
| **Third-party apps** | Everything the user installs | **Flatpak** (Flathub plus your own remote) | Independently, sandboxed |
| **Compatibility runtimes** | Wine runtimes, Waydroid images | Versioned bundles, side by side | Independently, pinned per app |

**Recommendation: an image-based, atomic, A/B-updated base plus Flatpak for apps.**

Why image-based rather than classic `apt upgrade`:

- Every user runs a byte-identical, tested base. Package-manager distros have a combinatorial explosion of possible system states — the source of most "works on my machine" support burden, which you cannot afford with non-technical users.
- **Updates are atomic and roll back.** A failed update reboots into the previous known-good image instead of leaving a half-upgraded, unbootable machine. For your audience that's the difference between a support ticket and a dead laptop.
- It pairs naturally with `dm-verity` and Secure Boot (§7).

Mechanism options: **`systemd-sysupdate` with A/B partitions and `systemd-boot`** (simpler, fewer moving parts, systemd-native — my recommendation), or **OSTree/`libostree`** (used by Fedora Silverblue and Endless OS; more mature, supports package layering, but a larger conceptual surface).

Build pipeline: `mmdebstrap` → your APT overlay → **`mkosi`** to produce the signed system image, the installer ISO and the A/B update artifacts from a single definition. `mkosi` is systemd-adjacent, actively developed, and designed for exactly this.

### 6.2 Your APT repository

Self-hosted with **`aptly`** (a better snapshot/promotion model than `reprepro`), signed with your own GPG key held offline. Channels `dev` → `beta` → `stable`, promoted by snapshot. Mirror upstream Debian rather than depending on `deb.debian.org` at build time — you want reproducible builds and no external outage able to stop your CI.

### 6.3 Third-party apps: Flatpak

Flatpak — not Snap (its backend is Canonical-controlled and proprietary, a direct conflict with your constraints), and not AppImage as the primary format (no sandbox, no update mechanism, no dependency story).

Ship Flathub enabled by default with your own curated remote layered on top for apps you have verified. Sandboxing via `bubblewrap` and `xdg-desktop-portal` — and **you must implement the portal backends for your shell** (file chooser, screenshot, screencast, settings, notifications). That portal work is a real and easily-underestimated chunk of Phase 3.

### 6.4 Installer

**Use Calamares for v1.** It is Qt-based (matching your shell stack), heavily themable, and handles the genuinely hard parts correctly — partitioning, LUKS, LVM, EFI, bootloader installation, locale, user creation. Every one of those is a place where a homegrown installer destroys someone's data. Brand it heavily; treat writing your own as a Phase 8 luxury.

Separately you need a **first-run setup wizard** inside the shell (welcome, network, account, privacy choices, app suggestions, enabling the Windows/Android layers). Write that one yourself — it's a first-impression surface and it's low-risk.

---

## 7. Update and security model

### 7.1 Updates

- **Atomic A/B system updates**, staged in the background, applied on reboot, with automatic rollback if the new slot fails to boot (boot counting via `systemd-boot`'s `LoaderBootCountPath`).
- **Sign everything:** image signatures verified before staging; APT repo GPG-signed; Flatpak repos signed.
- **Delta updates** to keep downloads sane — full images run ~2 GB; `systemd-sysupdate`/casync deltas keep typical updates to tens of MB.
- **Firmware via `fwupd`/LVFS.** Free, open, and what consumer hardware actually needs.
- User-facing policy: automatic security updates on by default, applied at reboot, with a clear "restart to finish updating" prompt. Never a modal that blocks the user mid-task — that's the Windows anti-pattern you're differentiating against.

### 7.2 Security baseline

- **Secure Boot.** Full chain: shim → `systemd-boot` → signed kernel → `dm-verity`-protected root. **Honest note, and it conflicts with one of your stated goals:** to boot on retail hardware carrying Microsoft's keys, your shim must be signed by Microsoft's UEFI CA. There is no open alternative — this is the one place the "no proprietary third-party services" principle cannot hold, unless you require users to enrol your key in firmware manually, which is unacceptable for non-technical users. The shim-review process takes months; start it early.
- **Full-disk encryption by default:** LUKS2 with the key sealed to the **TPM2** (PCR-bound), so the user gets encryption without a second boot password, plus a recovery key shown once during setup. The highest-value security feature for a consumer laptop OS.
- **`dm-verity`** over the read-only base image: tampering with the base is detectable and unbootable.
- **Immutable `/usr`.** `/etc` and `/var` writable; user data in `/home`.
- **AppArmor** profiles for network-facing services.
- **Sandboxing by default:** Flatpak apps, Wine prefixes (§3.4) and the Waydroid container all confined; portals as the only route to user files.
- **Module signing plus kernel lockdown** once Secure Boot is live.
- **A CVE response process.** You are now a distributor. Subscribe to Debian security announcements, the kernel CVE feed, and Wine/Mesa/Waydroid advisories. Define an SLA and mean it. This is an ongoing operational commitment, not a task, and it does not stop when you get tired.
- **Telemetry:** opt-in only, anonymous, self-hosted. Anything else contradicts the positioning.

---

## 8. Where you will need to learn new things

Stated plainly, since you asked.

| Area | Gap from your current stack | Effort |
|---|---|---|
| **Rust or C** | Manual memory, no GC, no runtime. Rust's borrow checker is a real curve, but far kinder than debugging use-after-free in a compositor. | 2–3 months to productive |
| **Wayland protocol model** | No web analogue: surfaces, buffers, damage, roles, seats, grabs. | 1–2 months |
| **DRM/KMS, Mesa, GPU buffers** | Modesetting, DMA-BUF, EGL/Vulkan interop, multi-GPU laptops, Nvidia's quirks. | 1–2 months, then ongoing |
| **Linux boot chain** | Firmware → bootloader → initramfs → systemd. `dracut`, unit ordering, `systemd-logind`, seats and sessions. | 3–4 weeks |
| **Debian packaging** | `debian/rules`, `debhelper`, `sbuild`, dependency and ABI hygiene, repo management. Tedious rather than conceptually hard. | 3–4 weeks |
| **Kernel configuration & patch maintenance** | Kconfig, patch-series maintenance, rebasing onto upstream. Not kernel *development*. | 3–4 weeks |
| **QML / Qt 6** | Closest to your existing skills — declarative, reactive, component-based. | 2–3 weeks |
| **Wine internals** | Prefixes, DLL overrides, `winetricks`, debugging via `WINEDEBUG` channels. A diagnostic skill more than a programming one. | 2–3 weeks |
| **UX design for non-technical users** | Genuinely the hardest non-code requirement, and the one most likely to be underinvested. Consider bringing in a designer. | Ongoing |

Things that transfer well: your .NET/C# background maps unusually cleanly onto Rust's type system and onto QML's binding model; SQL is directly useful for the compatibility database and package indexes; Python is used throughout Waydroid and build tooling.

---

## 9. Top risks

1. **Scope.** Four products in one. The most likely failure mode is 30 months of work with no shippable milestone. Mitigation: the phase plan is ordered so something boots and is demoable from Phase 1 onward.
2. **The shell is a bottomless well.** "As approachable as Windows" represents 20+ years of accumulated design work. Cut features ruthlessly; polish a small surface completely rather than shipping a wide, rough one.
3. **Hardware breadth.** Nvidia hybrid graphics, fingerprint readers, obscure Wi-Fi chips, suspend/resume. This is where consumer distros actually die. Define a small **certified hardware list** early and test on real machines.
4. **The Android layer's Google problem** (§4.3) may make the feature disappointing regardless of your engineering quality. Consider softening the promise from "runs Android apps" to "runs many Android apps."
5. **Wine as a malware vector** (§3.4). A consumer OS that runs `.exe` files unsandboxed is a liability. Do not ship without the sandbox.
6. **Solo maintenance burden.** Security response, hardware bug reports and support scale with users, not with features. Plan for community or funding before you plan for growth.
