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
manager's free memory as before); virtio-rng and the entropy service (D14: `entropy`); virtio-console, the shell
reached from a virtual machine's host through it (`console_port`); the kernel's lines until the system starts, and
its panic, on the framebuffer (C30, `panic_screen`); the IDL client's one in-place message buffer (A13; why not the
IPC buffer itself: IDL_RATIONALE.md).

The capability proof obligation from M2 remains partly open. Kani verifies a single copy
from a populated slot into an empty one. The exhaustive revoke test covers unmapped frames
and empty endpoints on bounded lists. A proof covering operation sequences and the other
object destruction paths is still owed.

A failed spawn returns outright grants to their original parent slots before
destroying the child's capability space. The `failed_spawn_returns_grants`
guest test checks the identity, rights and derivation depth of both an endpoint
and an Untyped after a later grant fails.

After boot, a successful provider start signals every running consumer of
that protocol. The `svcload` guest stops and starts partitions as a client,
checks its notification, and checks that starting it twice produces no
second notification.

The wall-clock reader makes at most two attempts to sample its time page. If a
writer exits mid-update, readers report unknown time until the next completed
write (`systest` runs the writer and reader as separate programs). The SNTP
decoder rejects timestamps before the Unix epoch. Authentication of the time
source and limits on the clock changes it may request remain open.

The log reader preserves byte offsets through malformed UTF-8 and carries a
valid character across a reply boundary whole. Filtering terminal control
characters on the console and in remote output remains open.

The shell splits long command output at UTF-8 character boundaries. The
terminal client test delivers 11,976 bytes through the generated wire codec
and compares the complete text. The x86_64 console guest covers the shell's
log, service and device commands on the keyboard and display.

The intermittent timeout after `fault_virtio_blk_stuck` was located in QEMU 11.1.3 on KVM. Eight copies of the
archived guest from the failed 20:29 run booted together on q35 with the original in-kernel irqchip. Seven exited
with status 33; one passed blkcheck, printed `BOOT OK` and timed out. QEMU traced two guest shutdown requests in
that VM. In a second batch of eight, the parent read QEMU's `shutdown_requested` via `/proc/<pid>/mem` during the
stall: 6 (guest shutdown), with its main thread asleep in `do_sys_poll`. Opening and closing the monitor socket
without sending a command made QEMU exit with the original debug-exit status 33. The normal test still requires
the VM to exit by itself. Run one fault case by its reported name, e.g. `tools/test.sh --guest fault_virtio_blk_stuck`.

The `systest` stop under `--full` on 2026-11-22 (QEMU exiting 0 mid-run, not through the debug-exit device) was the
guest resetting itself: on x86_64 every address-space root maps the kernel, and a processor idle or waiting for its
lock still ran on the root of a program another processor had just destroyed, whose memory a new object then
reused. Sixteen copies at a time, 240 runs: 7 failed (six resets, one double fault in the idle halt), 1 with idle
processors moved to the kernel's root, 0 with the handshake now in the kernel (a destroyed root's memory is reused
only after each processor on it has answered that it left; loom model and host test beside it). Under `-no-reboot`
QEMU traces no request for such a reset, so `qemu.sh` now names it when nothing asked the emulator to stop.

The idle watch's length no longer rests on one host's sweep: each processor's watch learns from its halts, and with
that in place 1, 2 and 5 us minimums give the same cross-processor IPC within the noise (2026-11-23; ARCHITECTURE.md,
Time). A boot-time measurement was tried and is not needed.

Still to build or explain, in order:

1. The performance gaps in `os/bench/open.tsv`. The session of 2026-11-24 on an idle host (desktop locked) closed
   the block reads at depth 1 (3.61 us, confined 4.26: their best), the confined round trip's p99 and
   cross-processor IPC on four pairs. Still open: the network round trip (9.05 us against Linux 10.23, 0.884;
   target 0.85; its line says what is next), boot (22.3 ms, red: the firmware's exit and the IOMMU set-up, and
   the owner's decision whether the metric counts them), transmit throughput 2% under its best, one
   cross-processor pair, the median timer overshoot, the page fault, and, new that session, context switch and
   same-processor IPC 1.1 to 1.4% under their best with their instruction counts unchanged (the host, not the
   code). Each line there says what it waits for.
2. `net_recovery` under `--fast` on 2026-11-23 (the desktop in use) saw one recovery of 656 ms against its 250 ms
   deadline. `netload` now says where a slow recovery's time went (until the next driver took the connection, with
   the tries, and from there to the first completion). Not reproduced since: 30 runs by name, 420 recoveries, the
   slowest 6 ms, 10 of the runs beside 16 busy processes. Waits for its next occurrence, which explains itself.
3. The hosted deep run. Run [45176778475](https://github.com/project-silica/os/actions/runs/45176778475/attempts/1)
   reported 75 failures: the runner's ARM firmware (2025.11-3ubuntu7.3) faulted before the loader, and
   nightly now selects 2026.05-2ubuntu3, installs cargo-fuzz and the instruction counter's headers, and
   archives fuzz build logs, benchmark serial output and check durations. The next,
   [45216348057](https://github.com/project-silica/os/actions/runs/45216348057) (2026-11-23), had 8:
   - The syscall fuzzer's seeds under their floor (1245 edges of 1347; 1259 here): each new syscall had
     changed every seed's meaning. Fixed on 2026-11-24 (kernel: a fixed SYSCALL_SPACE, the corpus carried
     across, 1764 edges); inet's `frames` was already above its new floor.
   - aarch64 `smp_stress`, `smp_revoke`, `smp_timeouts` and systest's `four_pairs_on_eight_processors`
     timed out while still running (the processors' PCs: one spinning in user mode by design, two in the
     IPC path), 8 emulated processors on the runner's 4 slow cores. Fixed on 2026-11-24 by judging
     progress instead of a total time: the tests count it and say it every 10 s, systest's clients signal
     it, and the harness ends a guest after a minute of silence (`qemu.sh --quiet`). With 8 processors on
     2 host cores here, systest passes in 463 s and smp_stress passes. The idle watch was suspected of
     starving such machines and is not: off and on gave the same times on 4 host cores. Verify on the
     hosted runner.
   - The fast tier took 95 s on the runner (limit 60 s; 160 s of work on 4 processors). Attributed here by
     each check's start and end (2026-11-24): of 51 s, 12 s was the console check typing (a process and a
     60 ms pause per key) and about 3 s finding objcopy twice per program in every build; both gone, 38 s
     now. The largest part left is the three recovery checks, 19 s alone by design. Measure the runner
     again on the next nightly.
   Without a dedicated
   TAP echo processor the benchmark guest ran netcheck without a NIC (reproduced exit 17). The harness
   now attaches a user-mode NIC on that host: ARP and ping pass and the guest reports BENCH DONE.
   The TAP-only network metrics still require their echo. The separate hosted typeahead timeout is
   consistent with a lost wakeup at console startup:
   the console now arms its empty input ring before the keyboard or port can publish buffered input.

M4 is built ahead while M3's first item waits for timed benchmark sessions on an idle desktop and its third for
the hosted run. Read against M4's exit test on 2026-11-24. Built: DHCP, SNTP, the wall clock from the hardware
clock, TCP for programs and 10,000 checked HTTP answers (`http_load`), the same over e1000e, the stack killed
under load (`http_restart`), the packet parsers fuzzed (`frames`, `tcp_peer`, `e1000e_device`), no periodic
wake-ups on the idle server (`idle`), a remote management session that inspects, restarts and updates any
service, the session's own included (`remote`, fuzz target `session`; ARCHITECTURE.md section 14), the program
loader's checks fuzzed (`image`), and the interop suite against the host's Linux stack over a tap (`interop`:
eight cases on a plain path, with a 536-byte MSS and an 8 KiB window, and with 2% loss, 1% duplication and 10%
reordering each way, and on the plain path 4 GiB + 16 MiB on one connection across the sequence-number wrap; it
found four defects, fixed: TIME-WAIT holding 64 KiB of buffers a connection for a minute,
every 32 KiB buffer a frame of its own so the stack ran out of capability slots at about 240 connections, a
finished stream closed at once losing its last bytes to a reset, and a server that died on a refused accept).
TCP under loss (2026-11-24): 16 MiB through the lossy path takes the guest 1.62 to 1.90 s in five runs of six (one
2.85 s), from 22 s at the start of that work, against Linux to Linux's 4.22 to 5.71 s on the same impairments
with Linux held to one segment per skb as the guest's frames are (ARCHITECTURE.md, TCP). The 0.08 to 1.1 s once
recorded for Linux was netem judging Linux's GSO bursts of up to 44 segments whole.
Still to build, in order:

1. The TCP gates of `spec/TESTING.md` section 4 measured against Linux on the same tap path as `net_rtt`, and
   the server image: its idle memory, and its size on disk (16 MB; `size.sh` skips it until an image of the
   server alone, without the checks, is built). The lossy comparison above becomes a gate there, its Linux
   number in `bench/reference.tsv`, measured the way ARCHITECTURE.md says. Built: the instrument, `tcpbench`
   (host-tools), measuring any guest's HTTP server from the host (first answer, p50 and p99 at a fixed rate
   over 64 connections, the virtual processors' time per GiB at a fixed rate); its first use found netd waking
   a program on every pass, fixed. The Linux baseline serves the same answers (`build_linux <log> server`,
   IPv4 and TCP in its config). First comparison, untimed and unpinned, 2 processors, the same tap
   (2026-11-24): HTTP p50 101.5 us Linux, 106 to 110 Silica; p99 176.6 and 187 to 252; the guest's
   processors per GiB at a fixed 200 MB/s 874 ms and 4,496 ms (5.1 times), at 50 MB/s 1,070 and 9,845 (9.2
   times). Built since: the device's transmit offloads (G14; `silica.net.Device` version 3, virtio-net, netd,
   ARCHITECTURE.md's TCP section): p50 80.8 us against Linux's 101.5, p99 197 against 176.6, the guest's
   processors per GiB 3.09 s at 200 MB/s and 3.83 s at 50 MB/s (Linux 0.87 and 1.07). Still to build, in order:
   (a) the guest's processors per GiB, the open gap `tcp_cpu_gb` (3.86 times Linux, timed): the idle
   watch is 71% of the guest's cycles at 200 MB/s; a 20 us cap cut a third untimed but cost depth-32 block
   reads 5.6% in the sweep, so the watch must spend only what the halt it avoids costs (its line in
   `bench/open.tsv`), then netd's copies; (b) e1000e's checksum and TSO context descriptors, so the second
   driver offloads what the device has. Built: the server group in `bench.sh` (`http_p50`, `http_p99`,
   `tcp_cpu_gb`, `boot_server`; `boot_server()`), Linux's numbers locked from one `--linux` session
   (2026-11-24, 8 processors): HTTP p50 92.5 us against 159.8 (0.58), p99 399 against 639 (0.62), boot to
   the first answer 66.7 ms against 1,187 (0.06).
2. The 24 h soak under mixed load: memory and capabilities flat, no request failed (a run on this host,
   its evidence committed).

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
