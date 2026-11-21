# Component inventory

The parts of the planned system, grouped by area. `spec/MILESTONES.md` refers
to components by these IDs, so they are stable. `M` is the milestone whose exit
test first needs the component. This is a map of the destination; build a
component when a working slice calls for it.

## A. Build, tooling, bring-up (M0)

- A01 Cargo workspace, pinned toolchain, custom target specs (x86_64, aarch64, riscv64)
- A02 `tools/init.sh`, `tools/test.sh` (`--fast`, `--full`, `--deep`, `--repo X`, `--guest NAME`), `tools/size.sh`, `tools/qemu.sh`, `tools/bench.sh`
- A03 Image builder: GPT disk image, ESP, kernel, initial ramdisk of core servers
- A04 QEMU runner with serial capture, timeout, exit-code device, screendump
- A05 Host test harness for `kernel-core` (std build), Miri and loom jobs
- A06 IDL compiler: `.idl` -> Rust client/server stubs, wire format, versioning checks
- A07 Fuzz harness scaffolding, coverage reporting
- A08 CI script runnable locally (`tools/ci.sh`) with fast and nightly tiers
- A09 Symbolizer and panic/backtrace decoder for serial logs
- A10 Reproducible builds check
- A11 Repository bootstrap: per-repo workspaces and READMEs, `os/manifest.toml`, `tools/sync.sh` with local path overrides, dependency-direction check (REPOSITORIES.md)
- A12 Hosted CI: reusable workflows that run `tools/ci.sh` on every push and nightly, compiler cache and toolchain image

## B. Boot (M1)

- B01 UEFI loader (Rust, `no_std`): load kernel + ramdisk, memory map, GOP info, ACPI RSDP, exit boot services
- B02 Boot protocol struct handed to kernel (versioned)
- B03 Early serial console, early framebuffer console
- B04 Secure Boot signing, measured boot (TPM2 PCR extend) (M5)
- B05 aarch64 boot (UEFI, device tree + ACPI), riscv64 boot (SBI) (M2, M8)
- B08 aarch64 completion for M2: guard pages below the kernel stacks (the boot stack and the other processors' stacks in the physical map have none), ASIDs so an address-space switch keeps the TLB, a device for the irq test on aarch64, E0PD so user reads of kernel addresses fault alike whether mapped or not (M2)
- B06 Kernel command line and boot config
- B07 A/B slot selection and rollback counter (M5)

## C. Kernel (M1 to M2)

- C01 Physical memory manager (buddy + per-CPU caches), NUMA-aware interface
- C02 Virtual memory: 4-level/5-level paging, huge pages, PCID/ASID, TLB shootdown
- C03 Untyped memory: retype into the ten object types, no kernel heap, zero allocation after boot
- C04 Object model (10 types), CapSpace, rights, derivation tree, revocation
- C05 Threads, context switch, FPU/SIMD state (XSAVE), TLS base
- C06 Scheduler: fair class, deadline class, scheduling contexts, idle, tickless, P/E core awareness
- C07 SMP bring-up, per-CPU data, IPIs, CPU hotplug interface
- C08 Syscall entry/exit (64-bit `syscall`/`sysret`, `svc` only; no 32-bit or compat entry), `libsys` vDSO, at most 32 syscalls
- C09 IPC: Endpoint call/reply fast path, Notifications, capability and Frame transfer
- C10 Frames, mapping, pager fault protocol, pinning (CoW is userspace policy)
- C11 Userspace libraries on Frames + Notifications: streams, channels, submission/completion rings (no kernel code)
- C12 Interrupts: x2APIC/APIC, IOAPIC, MSI/MSI-X (GICv3 on arm), all bound to Notifications; Hw capabilities for I/O ports (x86) and interrupt lines
- C13 Timers: TSC-deadline, HPET fallback, arch timers; expiry as Notification; monotonic clock
- C14 Exceptions and fault delivery to a supervisor Endpoint
- C15 Resource accounting, quotas, kill and teardown as userspace policy over Untyped revocation (no kernel code)
- C26 Bloat gates in `tools/size.sh`: kernel line count, syscall count, object-type count, static proof of no allocator in the kernel crate
- C16 IOMMU (VT-d, AMD-Vi, SMMUv3) domains as capabilities
- C17 ACPI table parsing (static tables in kernel; AML interpreter in userspace, see E03)
- C18 CPU feature detection, mitigations selection, microcode load hook
- C19 KASLR, W^X, SMEP/SMAP/CET, stack guards
- C20 Entropy source and kernel CSPRNG
- C21 Power: idle states (C-states), frequency hints (HWP/CPPC), suspend/resume hooks (M8)
- C22 Virtualization objects: Vcpu, guest address space (VMX/SVM, EL2) (M9)
- C23 Debug: kernel log ring, tracepoints, serial debugger stub, crash dump writer
- C24 Performance counters interface
- C27 Capability transfer through an endpoint (derive, duplicate or move, chosen by the sender), and a saved-caller reply capability so a server can answer calls out of order (M2)
- C28 Address-space table memory: grow a live AddressSpace's pool, give emptied tables back, PCID so a switch keeps the TLB (M2)
- C29 Notification bound to a thread, so one receive waits on an endpoint and on interrupts (M3)
- C31 Finer locks for capability and mapping operations once a measurement shows the all-processors lock or the single mapping lock limiting a workload (parallel page faults, process creation on many cores)
- C30 Early framebuffer console for the kernel's own messages on machines with no serial port (M3, with the local console)

## D. Core userspace (M2 to M3)

- D01 `init`/root task: owns all initial capabilities, starts the service manager
- D02 Service manager: manifest format, dependency graph, restart policy, capability routing
- D03 Process manager: `spawn`, ELF loader, dynamic linker, namespaces, process trees
- D04 Memory manager: default pager, swap/compressed memory policy
- D05 Component/package manifest format and resolver
- D06 `libsys`, native runtime, Rust `std` port (threads, sync, time, fs, net, process, env)
- D07 Allocator (userspace), TLS, unwinding, panic handling, crash reporter
- D08 Logging service, tracing service, metrics
- D09 Config store (typed, transactional, versioned)
- D10 Identity and session service (users, login, credential storage, biometrics hook)
- D11 Capability broker and permission prompts (the sudo replacement)
- D12 Secrets/keystore service, TPM2 access
- D13 Time service: RTC driver client, time zones (tzdata), NTP + NTS client, leap handling
- D14 Entropy service
- D15 Device manager: enumeration (ACPI, PCI/PCIe, USB, device tree), driver matching, hotplug
- D16 Power manager: battery, thermal, lid, suspend policy, shutdown/reboot
- D17 Update service: download, verify, write inactive slot, switch, rollback
- D18 Package service: content-addressed store, install, garbage collection, repositories, signing
- D19 Locale, i18n, text encoding, collation (ICU-subset)
- D20 Shell (typed pipelines over channels) and core utilities
- D21 Remote management service (authenticated, encrypted; the SSH equivalent); SSH protocol server implemented natively
- D22 Terminal emulator protocol and PTY-equivalent service
- D23 Machine description: one typed document for base version, packages, settings, users; transactional apply; bootable generations
- D24 Content-addressed library sharing: store-once on disk, share-once in memory, per-package component list
- D25 Public package log and static-file repositories; reproducible-build verifier

## E. Drivers (M2 to M8)

- E01 Driver host, driver framework crate, class protocols in IDL
- E02 PCI/PCIe bus driver (ECAM, MSI-X, capabilities, SR-IOV awareness)
- E03 ACPI AML interpreter service; EC, battery, thermal, buttons
- E04 virtio: blk, net, console, rng, gpu, input, fs, balloon, sound
- E05 NVMe, AHCI/SATA, USB mass storage, SD/eMMC
- E06 xHCI, USB hub, HID (keyboard, mouse, touchpad, gamepad), USB audio, USB serial, USB-C/PD policy
- E07 Ethernet: e1000e, igc, one 10G+ NIC
- E08 Wi-Fi: one family (chosen at M8) + regulatory domain; Bluetooth HCI + HID/audio profiles
- E09 Display: GOP/simple framebuffer, virtio-gpu, one native modesetting driver, EDID, hotplug, multi-monitor, HiDPI, VRR
- E10 GPU: Venus (virtio-gpu Vulkan), one native GPU family (chosen at M8)
- E11 Audio: Intel HDA, USB audio class, virtio-sound
- E12 Input extras: I2C HID, touchscreens, tablets
- E13 RTC, HPET, watchdog, TPM 2.0 (CRB/TIS)
- E14 Camera (UVC), printers (IPP over network only)
- E15 Platform: SMBIOS, firmware update (UEFI capsule), CPU microcode
- E16 Driver porting pipeline: behavior descriptions, register-definition generator, per-class frameworks (ARCHITECTURE.md section 15)
- E17 Driver verification rig: register-trace capture and comparison against a reference driver, per-driver benchmark gate
- E18 Driver packages: manifest device matching, independent update, automatic rollback of a repeatedly crashing driver

## F. Storage (M3 to M5)

- F01 Block server, request rings, partition (GPT) service, I/O scheduler
- F02 VFS/namespace server: directory capabilities, path resolution, watches
- F03 Native CoW filesystem: format, allocator, B-trees, checksums, snapshots, send/receive, scrub, fsck, crash consistency
- F04 Package blob store (Merkle-verified, read-only)
- F05 FAT32/exFAT, read-only ext4, ISO9660/UDF read
- F06 Encryption layer, key management
- F07 Page cache / buffer cache service, mmap of files via pager protocol
- F08 tmpfs, pipes-equivalent (channels with stream semantics)
- F09 Volume manager (multi-device, mirroring) (M8)
- F10 Network filesystems: one of NFSv4/SMB3 client (M8)
- F11 Quotas, per-app storage sandboxes
- F12 Backup/snapshot scheduling service

## G. Network (M4)

- G01 Netstack core: interfaces, routing, neighbor tables, sockets API in IDL
- G02 IPv4, IPv6, ICMP/ICMPv6, NDP, ARP, fragmentation, PMTU
- G03 TCP (SACK, window scaling, timestamps, ECN, CUBIC + BBR), UDP, raw sockets by capability
- G04 DHCPv4, DHCPv6, SLAAC, RA handling
- G05 DNS stub resolver, cache, DoT/DoH, mDNS/DNS-SD
- G06 TLS 1.3, certificate store and verification, OCSP stapling
- G07 QUIC and HTTP/1.1, HTTP/2, HTTP/3 client library
- G08 Packet filter / firewall, NAT, per-app network capabilities
- G09 WireGuard; IPsec later
- G10 Wi-Fi supplicant (WPA2/WPA3), network manager, captive portal detection
- G11 Bridge, VLAN, bonding, TAP for VMs (M8)
- G12 Loopback, local inter-process sockets (channels)
- G13 Network diagnostics tools (ping, trace, capture)
- G14 Zero-copy path, RSS, GRO/GSO, checksum offload
- G15 Time sync hooks (PTP later)

## H. Graphics and desktop (M6)

- H01 Display server + compositor: surfaces, buffers, damage, frame timing, vsync, multi-output, HiDPI scaling
- H02 Software renderer (SIMD, tiled), blur/glass pipeline, color management (sRGB, wide gamut, HDR hook)
- H03 Input stack: keyboard layouts (xkb data), IME framework, pointer acceleration, gestures, touch
- H04 Font stack: discovery, shaping, rasterization, subpixel, emoji, fallback, bidi
- H05 UI toolkit: layout, widgets, theming, animation, accessibility tree
- H06 Window management: tiling + floating, workspaces, snapping, fullscreen
- H07 Shell: panel, launcher, notifications, system tray, quick settings, lock screen, login screen
- H08 Clipboard, drag and drop, screenshot/screen record (by capability)
- H09 Accessibility: screen reader, magnifier, high contrast, keyboard navigation
- H10 Audio server: mixing, routing, per-app volume, low-latency path
- H11 Media: image decoders, audio/video codecs (hardware decode hook), camera pipeline
- H12 Printing and scanning service
- H13 File dialogs and portals (the capability-granting UI)
- H14 Core apps: terminal, file manager, settings, text editor, system monitor, image viewer, installer
- H16 Vulkan loader/ICD interface, `wgpu` backend (M8)

## I. Developer platform and languages (M5 to M9)

- I01 Rust target triple upstreamable, `cargo` works on-device
- I02 WASI component runtime, capability mapping
- I03 C-ABI system library: generated C/C++ bindings for every IDL protocol; native concepts only, no POSIX names
- I04 LLVM target triple, lld support, minimal freestanding C runtime (memory, math, startup, unwinding); C, C++, Zig, Swift build natively
- I05 SDK: IDL docs, templates, emulator image, debugger (gdb/lldb remote stub), profiler
- I06 Language runtimes on the WASI component runtime: Python and JavaScript first; standard-library backends for the native API per language
- I07 Servo ported natively (M7)
- I08 IDL binding generators for additional languages; binding conformance tests
- I09 Container-like isolation for server workloads (process trees + namespaces + package images)
- I10 Hypervisor service on Vcpu for isolated guest workloads (server feature, M9)

## J. Security, reliability, release (continuous)

- J01 Threat model document; capability audit tool (who can reach what)
- J02 Syscall fuzzer, IPC protocol fuzzers, filesystem image fuzzer, network packet fuzzer
- J03 Kani proofs for capability derivation/revocation and IPC state machine
- J04 Fault injection: kill any driver or server under load; system recovers
- J05 Soak tests (24 h, 72 h), memory-leak and handle-leak detection
- J06 Performance benchmark suite and regression gates (see TESTING.md)
- J07 Crash reporting pipeline, symbol server
- J08 Installer, recovery environment, factory reset
- J09 Documentation: architecture book, driver guide, app guide, generated IDL reference
- J10 Release engineering: API levels, date-based OS versions, nightly/beta/stable promotion, signing, component lists, public release log (CI_RELEASE.md sections 7 to 9)
- J11 Licensing audit of vendored crates
- J12 Telemetry: off by default, documented
