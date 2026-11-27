# Milestones

Each milestone has an exit test (the table below). The list under "What the current milestone lacks" is what the
code does not do yet against that test; its first item is what to build next. A commit that builds an item, or finds
one missing, changes the list with it. An exit test is a floor: strengthen one that passes while the system plainly
is not dependable for what the stage claims.

## Required at every milestone

Each exit test includes these, for everything built up to that point:

- Every size budget and every performance gate due by then passes (`spec/ARCHITECTURE.md` section 2, `spec/TESTING.md` section 4), every metric stays above its Linux floor in `os/bench/reference.tsv`, no metric due by then has an open gap (`os/bench/open.tsv`), and every path the milestone's work touched was tuned until its profile showed only work the hardware or a guarantee requires.
- The boot matrix passes: 1, 2, 8 and 64 vCPUs, with 256 MB and 16 GB of RAM.
- Every new trust boundary (syscall, protocol decoder, on-disk or on-wire parser, device response) has its promise written beside the code, an attack test that fails when it breaks, and a fuzzer that runs 10 minutes clean.
- Every new restartable component has been killed under load and has recovered inside its deadline with nothing leaked.
- Every new published protocol has documentation generated from its source and a client written from that documentation alone.
- The owner can inspect every new component with the tools available at that stage: its state, its capabilities and its log.
- Each new error path is exercised by a test and reports what failed and why.
- Whatever the new layer had to work around in a lower layer is fixed in the layer that owns it before the next milestone builds on it.

A milestone is declared once, when its list is empty: from a fresh clone, `SILICA_MILESTONE=<n> tools/test.sh --deep --fresh` is green with no test skipped or weakened. That run declares a milestone and has no other use.

## What the current milestone lacks

M3 (M4 is built ahead of it; both lists are open). What is built, and the evidence for it, is in the commits.

M3:

1. The performance gaps in `os/bench/open.tsv`, each with what it waits for: the network round trip, boot (the
   firmware's exit and the emulated IOMMU set-up, and the owner's decision whether the metric counts them), transmit
   throughput, one cross-processor pair, the timer's median overshoot, the page fault, context switch and
   same-processor IPC. Timed runs need an idle host. (The instruction-count costs of the run-queue tree, scheduling
   contexts and the lock share are won back: every counted path is below its old best.)
2. Timed runs owed for paths changed without one: netd's segment lookup and transmit pass, the drivers' deadline
   lookup (`blk_read4k_qd1`, `net_rtt`), the heap.
3. `net_recovery` once took 656 ms against its 250 ms deadline under `--fast`; not reproduced in 420 recoveries.
   `netload` now says where a slow recovery's time goes.
4. The hosted runs. The fast tier fits the pre-merge job again, as two jobs (`SILICA_SHARD`): on 2026-11-27 its two
   halves took kernel 148 and 89 s, system 126 and 112 s, os 163 and 96 s of the 215 s each may. On the runner
   aarch64's `smp_*` and systest finish (nightly 45820995808: `smp_stress` 316 s, `smp_revoke` 271 s, systest 914 s).
   The nightly does not finish: Miri on kernel-core is some 47,000 s of processor time, its slowest tests an hour or
   more each by the size of the machine they build (64 MiB zeroed and retyped under the interpreter), past what 6
   hours on the runner's 4 processors holds (cancelled at 6 h on 2026-11-26). Owed: those tests' machines made as
   small under Miri as what they show allows, as the queued-threads test already cuts its threads; then the other
   failures of the last nightly that finished (2026-11-25: the ELF fuzzer's committed seeds below their coverage
   floor, one error in 10,000 requests of `http_load_e1000e`, `interop`'s server never listening, `idle` needing
   KVM statistics a hosted runner cannot give) on the next one that does.
5. The capability proof: Kani verifies one copy and the exhaustive check covers revoke over bounded lists of frames
   and endpoints; a proof over operation sequences and the other destruction paths is owed.
6. Placement (ARCHITECTURE.md, Placement), each stage the default only when it measures better at 1, 2, 8 and 64
   processors on latency (`net_rtt`, `http_p50`, `http_p99`, depth-1 block reads), throughput (`net_tx`,
   `http_load`, depth-32 block reads) and processor cost (`tcp_cpu_gb`), with no idle wake-up and isolation
   unchanged, against all-on-0 and the alternatives tried:
   a. Topology in the root task's start record; management services on a housekeeping processor; each data-path
      service and its device's driver placed in one cache domain by role, not by number.
   b. A path per processor: `silica-queue` queues per submitting processor, multiqueue virtio-net, NVMe queues per
      processor, netd and the block path sharded by flow and by queue.
   c. The kernel's imbalance event and a balancer service that moves scheduling contexts on it.
7. Owed on real hardware (M8): the IOMMU's RMRR ranges, AMD-Vi, Arm SMMUv3, interrupt remapping's old-format block,
   the idle watch's length, the e1000e NVM wait; the `unconfined`, `rogue_tcg` and `idle` guests run there.
8. Recovery and isolation built (panic record and reset, the watchdog taken on the device manager's signal, checked
   arithmetic, `secrets` isolation, the low-memory signal, ordered shutdown). Owed: the device manager taking each
   device's IOMMU fault notification itself (today the attaching driver gets it, and a hostile one can ignore it;
   until then a refused interrupt message, or a device on a bus with no context table, holds its unit's fault
   interrupt until a device space is inspected); a provider that spends a call's donated time without answering,
   reported by the kernel to its supervisor (what replaces the hung-provider probe, removed as a guess anyone could
   trigger);
   a watchdog on aarch64 (QEMU's `virt` has none; `sbsa-gwdt` on the sbsa-ref machine or hardware); a guest test
   of an MSI storm (host model only), of devices above bus 64 (the device manager does not scan an expander's root
   bus), and of SError containment (needs RAS hardware); an in-OS test moving a line on aarch64 (`irq_follow` is
   x86_64 only: its device is the 16550); netd as the first caller of `mem::watch_low`.
9. With M5's storage: updates land in the inactive image and switch at the next boot with rollback (until then
    `update` says it lasts until a reboot), and logd keeps a bounded log on disk.
10. `--fast --fresh` takes 91 s against M0's 60 s (`fast_budget`): 18 s of builds and lint, 27 s of recovery tests
    run alone, then the guest boots, eight at a time. A check joins a boot that has its image before it gets its own
    (`net_crowd` now runs in `net`'s); the rest are the same kind of merge, guest by guest. Some still wait out the
    time limits their attacks test (replayed and silent sessions, SNTP's agreeing answers): a peer's limit belongs
    to that peer, so a test image's peer gets a short one in its own declaration or file, as `remote.owners` does.
11. Facts still learned from a clock, each to be told instead: the block client retries a restarted driver on a
    clock (netd watches its class; the block client should too), with a test of a driver away longer than the old
    5 s; `connect` before a lease is answered `no_address` and polled (park it until the lease, bounded per
    program); netcheck and netload wait for a device with `yield_now` (`watch`); accept is a polling call (blocks
    posted ahead and filled by the stack).
12. Seen once, in the `--fast` run inside a `--full` (2026-11-26): the `remote` test's owner stopped mid-upload of a
    program after 5 calls and its session closed on its 6 s idle bound; not seen in the five runs after. Owed: what
    held the owner's bytes (the host's sends, netd's receive window, virtio-net's receive queue), from a run that
    keeps netd's counters with the serial log.
13. netd's TCP table has no host test: the listener without a backlog (what waits takes places the program paid
    for) and the reset of an evicted handshake are seen only through guests. Owed: a host test of netd's TCP table,
    and with it, at a program's bound, the handshake a new SYN evicts reset and its place given to that SYN at once
    (today the evicted one holds its place until its reset is sent, so the SYN that evicted it is refused).
14. The NMI findings of the review of the kernel's hot paths are built (an NMI from user mode is heard before the
    lock and lets NMIs in again; the paranoid entry compares the GS base with the processor's own; NMI, double fault
    and machine check have a stack each). Owed: a test that forces the windows they close (an NMI whose entry
    switches threads, an NMI inside the swapgs window, a machine check and an NMI together), which needs a test
    hook in the entry path (`harness`).
15. Before devmgr lends a driver its registers, establish ownership of the whole mapped range, including padding
    to a page. Check equal BARs on different functions, overlapping large BARs and overlap with firmware memory.
    Read back a newly placed BAR before using its address.
16. The boot chain at M5 must authenticate the archive and kernel options along with the executable images.
    The test changes each input separately and requires the loader to name the refused input before starting it.
17. Removing a capability walks every waiter of its queue under every lock (`revoke_waiters`, from `clear_slot`):
    bounded by one thread object a waiter, but with no point to stop and resume, unlike revoke, delete, unmap and
    an address space's end (the 2026-11-27 audit's M12). Owed: a resumable walk, by a queue generation the IPC fast
    paths would pay for or a waiter list per slot, each measured with `bench.sh --only insns`.
18. The 2026-11-27 audit's low findings not yet built: the service manager keeps every program hash `list` has
    shown for good (32 bytes for each distinct program an `update` brings, as `list`'s reply borrows them for the
    life of the system); a partition is numbered `disk << 8 | index`, so a disk on a PCI segment above 255 shares
    its partitions' numbers with another disk (refuse such a disk's table by name, or widen the number);
    `silica.system.Manager`'s handlers in the service manager and the device manager's client handlers have no
    fuzzer; a driver restarted on `AGAIN` is bounded only by a client having opened it since it started; the
    runtime heap's lock is held across system calls; logd copies log bytes one at a time; `describe` inspects each
    slot three times.

M4 (built: DHCP, SNTP, the wall clock, TCP for programs, HTTP under load and over e1000e, the stack killed under
load, packet parsers fuzzed, no periodic wake-ups, remote management, interop with Linux including hostile peers,
the server image):

1. The TCP gates against Linux: `tcp_cpu_gb` is 3.86 times Linux (the idle watch is most of the guest's cycles:
   it must spend only what the halt it avoids costs, then netd's copies); the lossy-path comparison becomes a gate;
   the server image's idle memory.
2. e1000e's checksum and TSO context descriptors.
3. The 24 h soak under mixed load: memory and capabilities flat, no request failed.
4. Remote's machine key now comes from the loader's boot-services-only UEFI variable. With M5's sealed storage
   and authenticated boot, prove that changing the boot volume cannot expose the key and that changing firmware
   variable access cannot replace the machine's identity undetected.
5. Authenticated time (NTS); a DHCP-supplied server can still set the first clock within the sanity bounds.
   Duplicate-address probing (RFC 5227) before using a lease.
6. TCP keepalive for idle connections.
7. The manager sees remote as the caller for every owner. Give each authenticated owner a capability restricted
   to that owner's services and methods, and have the manager enforce it. Exercise two owners with disjoint grants.
8. The hosted HTTP load test on virtio-net lost two answers out of 640 (system run 45998606875).
   Capture the stream state for a stalled request while other clients are still receiving answers. A lead to check
   first: `Tcp::sleep` keeps netd awake for a ring with bytes ready without marking that connection due.

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
