# Milestones

The exit test says what a milestone must do. The list under "What the current
milestone lacks" says what the code does not do yet, found by reading the code
against the exit test; its first item is what to build next. A commit that
builds an item, or finds one missing, changes the list with it. Engineering can
proceed as soon as the technical prerequisites exist.

An exit test is a floor. It passes when the system at that stage is something
its users could depend on for what the stage claims, so strengthen a test that
passes while the system plainly is not, and add what it failed to anticipate.

## Required at every milestone

Each exit test includes these, for everything built up to that point:

- Every size budget and every performance gate due by then passes (`spec/ARCHITECTURE.md` section 2, `spec/TESTING.md` section 4), every metric with a Linux number in `os/bench/reference.tsv` meets its target of 15% better than it, and no metric due by then has an open gap (`os/bench/open.tsv`).
- The boot matrix passes: 1, 2, 8 and 64 vCPUs, with 256 MB and 16 GB of RAM.
- Every new trust boundary (syscall, protocol decoder, on-disk or on-wire parser, device response) has a fuzzer that runs 10 minutes clean.
- Every new restartable component has been killed under load and has recovered inside its deadline with nothing leaked.
- Every new published protocol has documentation generated from its source and a client written from that documentation alone.
- The owner can inspect every new component with the tools available at that stage: its state, its capabilities and its log.
- Each new error path is exercised by a test and reports what failed and why.
- The decisions underneath have been tested by this milestone's work. Whatever the new layer had to work around in a lower layer, such as an awkward protocol, a missing concept, or a cost that should not be there, is fixed in the layer that owns it before the next milestone builds on it.

A milestone is declared once, when its list below is empty: from a fresh clone, on the image the tools build, `SILICA_MILESTONE=<n> tools/test.sh --deep --fresh` is green with no test skipped or weakened to get there (every check ran on that tree, nothing read back from the evidence store, and Silica measured on it). That run declares a milestone and has no other use; it is not how the list is found.

## What the current milestone lacks

M3, read against its exit test and the requirements above on 2026-11-22. Built already: the service manager
booting from declarations; virtio-blk, virtio-net and NVMe in userspace, confined, each with a hostile driver in its
place and the unconfined image; drivers killed under load (`recovery`, `net_recovery`, `recovery_nvme`); device fault
injection; the keyboard and display drivers restarted under the shell; disk hot-add and removal; shutdown and reset;
`trace`, `log` and `caps` in the shell; fuzzers for M3's trust boundaries, each 10 minutes clean (`virtqueue`: the
used ring of virtio-blk, -net and -input; `nvme_controller`: completion entries, Identify data and CAP;
`pci_config`: configuration space as the device manager and a driver read it; `ring`: `silica-queue`'s and the log's
rings with a hostile peer; `gpt`); interrupt remapping (C32: a device raises only the interrupts its driver bound,
shown by the hostile driver's forged message refused under `rogue_tcg`; the old-format block is owed on real
hardware, COMPONENTS.md); services killed under their clients' load (`svcload`: partitions, logd, console,
shell and the device manager restarted ten times each, every recovery inside the 250 ms deadline (the device
manager's 65 ms, the others' under a millisecond), no read or log line lost, no client failing, the service
manager's free memory as before). Still to build, in order:

1. `fault_virtio_blk_stuck` fails about one run in four on a loaded host: every check passes and `BOOT OK` is
   printed, then the kernel's power-off (QEMU's debug-exit port, then ACPI S5) returns without the machine stopping,
   and QEMU runs to its timeout with its main loop idle and both processors halted (`qemu.sh` now keeps the
   emulator's thread states beside the serial log on a timeout). No other test has shown it. Find the race and fix it.
   Related or not: under `--full` on 2026-11-22, `systest` (x86_64, eight processors) stopped once mid-run with QEMU
   exiting 0, not through the debug-exit device, with no reset and nothing on stderr; it passed 6 of 6 alone.
   `qemu.sh` now says what asked the emulator to stop (shutdown cause, run state, watchdog), so the next one explains
   itself.
2. virtio-console: an M3 device with no driver (virtio-rng and the entropy service, D14, are built: `entropy`).
3. The kernel's own messages and its panic on the framebuffer (C30), for a machine with no serial port.
4. The IDL client encodes into and decodes from the IPC buffer (A13): `idl/rt/src/client.rs` keeps a request and a
   reply buffer of `MAX_MESSAGE` bytes each and copies each way.
5. The idle watch's length from the halt-and-wake cost each machine measures at boot, instead of 5 us swept on one
   host (ARCHITECTURE.md, Time), before drivers are tuned against it.
6. The performance gaps in `os/bench/open.tsv`: block reads at depth 1 and their p99, block reads at depth 32, the
   network round trip and the null system call against Linux; boot time, timer overshoot, and the IPC and page-fault
   instruction counts against their ratchets. Each line there says what change it waits for. The timed block and
   network paths have not been measured since interrupts were remapped (QEMU's I/O APIC moved to userspace under
   KVM, and each route translated by the IOMMU): `bench.sh --only blk,net` when the desktop is idle says what it cost.

## Exit tests

| M | Name | Components | Exit test |
| --- | --- | --- | --- |
| M0 | Harness | A01-A12 | An empty kernel stub builds for 3 targets; `--fast` runs under 60 s and reports `RESULT:`; IDL compiler round-trips a sample protocol and matches the known-answer vectors; a deliberately failing test prints one `ERROR:` line; two builds from different directories are byte-identical. |
| M1 | Boot and kernel core | B01-B03, B06, C01-C05, C08, C12-C14, C23, C26 | Boots under OVMF across the boot matrix, prints over serial, runs one userspace thread that makes a syscall and exits. A userspace fault (bad pointer, illegal instruction, stack overflow) is delivered as a fault message and the kernel keeps running. A kernel panic prints a backtrace that `tools/symbolize.sh` decodes to function, file and line. The syscall fuzzer runs 10 minutes with no panic, no leaked capability and balanced Untyped. Reference-model tests for objects and memory pass; kernel size budget and bloat ceilings met; boot time to first userspace instruction recorded. |
| M2 | IPC, SMP, capabilities | C06, C07, C09-C11, C15, C17-C20, C24, D01, D03, D06 (libsys and native runtime), B05 (aarch64) | Two processes exchange 1M IPC round trips on 8 vCPUs with no loss, and again while a third process revokes and regrants the endpoint. A process that exhausts its Untyped gets an error and no other process is affected. A capability revoked in the middle of a call fails that call with the documented error on both sides. Capability fuzz 10 min clean; the proofs of no-forge (Kani) and revoke completeness (exhaustive over every derivation list of up to five slots and every interrupt pattern, since Kani did not finish it) pass; loom clean on the IPC fast path. An echo client and server written from the generated documentation alone build and run. A debug console lists every thread, its state and every capability it holds. aarch64 boots to the same test. IPC, context-switch and boot gates met. |
| M3 | Drivers and services | D20 (console shell), D16 (shutdown, reboot), E05 (NVMe), C16, D02, D04, D07, D08 (logging), D09, D14, D15, E01, E02, E04, E16, E17, F01, F08 | Service manager boots the system from manifests. virtio-blk and virtio-net run in userspace, each holding only its device's capabilities with DMA confined by the IOMMU (shown by a hostile driver in each one's place failing at every boundary, and by the same image booting on a machine without an IOMMU and saying that it is unconfined), and each at or better than the Linux driver on throughput and p99 latency on the same device. Killing either under sustained load recovers within 250 ms with no committed write lost and every outstanding request completed or failed cleanly. Fault injection (garbage completions, stuck queues, spurious and missing interrupts, device reset) crashes nothing outside the driver. An NVMe driver, written from the class protocol documentation alone against QEMU's NVMe model, is under 3,000 lines and passes the same tests. A keyboard on the local console drives a shell on the framebuffer, and both keep working when their drivers are restarted under the running shell, a disk hot-added at runtime appears and is usable (and can be taken out again), and the system shuts down and reboots cleanly on request. A request can be traced across client, block server and driver from the shell (the shell's `trace`), and every service's log and capabilities can be read there (`log` and `caps` in the shell, for services and for drivers). |
| M4 | Network server | E07 (e1000e), E13 (RTC, watchdog), G01-G08, G12-G15, D13, D21, D08 (tracing and metrics) | Image boots, gets DHCP, syncs time, serves 10k HTTP requests from the host (64 concurrent connections, response sizes from 1 KB to 1 MB, every body checked against its expected hash, zero errors), keeps wall-clock time from the hardware clock before the network is up, runs the same tests over an e1000e interface, accepts a remote management session that can inspect, restart and update any service. Killing the network stack under load resets its connections cleanly and service resumes within 1 s. Every packet parser fuzzed 10 min clean; interop suite green against the host Linux stack. A 24 h soak under mixed load shows no growth in memory or capabilities and no failed request. The idle system makes no periodic wakeups. Boot, idle-memory and TCP gates met. **This is the server deliverable.** |
| M5 | Storage, security, updates | E13 (TPM), F02-F07, F11, F12, B04, B07, D05, D06 (Rust `std` port), D10-D12, D17, D18, D20, D22-D25, E18, I01-I03, J01-J04 | Install to disk, reboot, update A to B, corrupt B, automatic rollback. Crash-consistency suite green with power cut at every block boundary, and a full disk returns errors without corrupting anything already committed. Secure Boot chain verified. A WASI app and a C program built against the native C bindings run sandboxed: each reads a file from a directory it was granted, is refused a sibling directory and the network, and gets the documented error when the grant is revoked mid-run. A Rust program using `std` (files, sockets, threads, time) builds unmodified for the Silica target and passes its tests on the image. Storage gates met. |
| M6 | Desktop | E09 (GOP, virtio-gpu), E06 (HID via QEMU xHCI), E11 (virtio-sound), H01-H10, H13, H14, D19 | Boots to login, logs in, opens terminal + file manager + settings with glass panels at 60 fps in software at 1080p on 4 vCPUs, with input-to-frame latency at or below one frame. A document typed in the editor, saved, and reopened after a forced power-off has the same bytes. Killing the compositor or any app restores the session without a reboot and without losing saved state. The idle desktop makes no periodic wakeups and fits its memory budget. All screens match goldens; full keyboard navigation; accessibility tree complete. **This is the desktop deliverable.** |
| M7 | App platform | I04-I06, I08, I07, H11 | On-device `cargo build` of a native GUI app, and of the Silica kernel itself, producing the same bytes as the host build. A Python program and a JavaScript program run on the component runtime, each built on the third-party package chosen for its language before M7 work began, and each reading a granted file, waiting on a timer, making an HTTP request, and being refused a directory it was not granted. A native application written from the SDK documentation alone by someone who has not seen the system's source builds, runs and is packaged. Servo renders a set of reference pages matching goldens and completes a login, a form submission and a file download on live sites. |
| M8 | Real hardware and GPU | E03, E05, E06 (the rest), E07, E08, E09 (the rest), E10, E11 (the rest), E12-E15, C21, D16, H16, F09, F10, G09-G11, B05 (riscv64) | Boots and passes `tools/test.sh --full` on one named reference laptop and one named reference server. On the laptop: Wi-Fi, audio, external display, 100 suspend/resume cycles with no failure, and battery life at or better than Linux on the same workload. On the server: NVMe and network at or better than Linux on throughput and p99 latency. One week of daily use on the laptop with every failure recorded and fixed. Vulkan conformance subset passes on Venus. Requires a human with hardware. |
| M9 | Virtualization and release | C22, I09, I10, J05-J12, H12 | The hypervisor service boots an isolated guest; 72 h soak clean on both reference machines; installer and recovery work from blank disk and from a corrupted system; the outside-developer trial is complete and its findings are fixed; an independent security review of the kernel, IPC and update path has no open high-severity finding; release artifacts signed with SBOM. |

## When devices arrive

Each device class gets its first driver and its first real caller in the same milestone, and a second driver for a
non-virtio device model soon after, so the class protocol is proven before more is built on it. Everything up to M7
runs on QEMU's device models; M8 is real hardware.

| M | Devices and platform services that must work |
| --- | --- |
| M1 | Serial console; the firmware's framebuffer, entropy and wall-clock time handed over to the root task at boot |
| M2 | Per-CPU timers; interrupts routed to userspace |
| M3 | PCI enumeration; virtio-blk, virtio-net, virtio-rng, virtio-console; NVMe as the second block driver; framebuffer text console (userspace, plus the kernel's panic screen); keyboard (virtio-input) on a local console shell; hot-add and removal of a device; shutdown and reboot |
| M4 | Hardware clock, NTP and time zones; e1000e as the second network driver; watchdog |
| M5 | Storage on NVMe and AHCI models; TPM 2.0 for measured boot and disk keys |
| M6 | Display (GOP, virtio-gpu, two outputs); pointer and keyboard through xHCI and USB HID with hotplug; keyboard layouts; audio out and in (virtio-sound, then the HDA model) |
| M8 | The reference laptop and server: internal keyboard and touchpad, Wi-Fi, Bluetooth, battery, thermal, lid, suspend, a native GPU, camera, USB storage, external displays |

External device, signing and release trials are prerequisites for their respective
exit tests. Track their availability separately while local work continues.
