# Testing Silica

Run `tools/test.sh --fast` for host tests, target builds and a QEMU boot. Run `--full` for host and guest coverage, Miri, loom and tool regressions, or `--deep` to include fuzzing. Run a single guest case with `--guest NAME`. Additional guest tests are listed in `kernel/tests/inos-<architecture>.txt`, one name per line. The result and failure details are available under `target/logs/`.

## 1. What finished means

A change is finished when the integrated image boots with it, a test exercises it through the interface a real
caller would use, its failure path produces a message someone could act on, and its cost has been measured.

Ask these of every component before calling it finished. They are what "professional" means for an operating system.

- **Trust boundaries hold.** Nothing a less trusted party sends can crash, hang or confuse a more trusted one. The
  kernel survives any syscall argument, a server any message, a driver a device that returns garbage, a parser any
  bytes from disk or network.
- **Committed data survives.** A power cut, a crash, a killed driver or a failed update never loses or corrupts
  something the system reported as written.
- **Every failure is handled and explained.** Each error path exists, is tested, and reports what failed and why
  in terms the caller or the owner can act on. Running out of memory, queue space or capabilities is an error
  returned to the caller.
- **It behaves at the edges.** Under sustained load, at the limits (64 CPUs, 256 MB of RAM, a full disk), when a
  device disappears mid-request, across suspend and resume, and after the component is killed and restarted.
- **Timing comes from the hardware or the protocol.** A delay tuned until the test passed fails on the next machine.
- **Authority is minimal and visible.** Each process holds the capabilities its job needs, and the owner can see them.
- **Interfaces say what they mean.** A published protocol documents who owns each buffer and capability, what each
  error means, what ordering is required and what happens on reset, generated from the source.
- **Results repeat.** Builds are reproducible, tests are deterministic, and a performance claim comes with the
  command that reproduces it.

Tests verify correctness; they do not define the solution. Code that passes by special-casing the test's inputs is
wrong, and a test that is itself wrong is fixed and the fix explained.

## 3. Oracles by layer

An OS has no single reference implementation, so each layer gets its own.

| Layer | Oracle |
| --- | --- |
| Kernel objects, caps, IPC | Executable reference model in plain Rust (simple, obviously-correct, slow). Proptest drives random operation sequences against model and real implementation and compares state. Kani proves no-forge and revoke-completeness on bounded configurations. |
| Scheduler | Deterministic simulation on host: synthetic workloads, assert fairness bounds, deadline admission, no starvation, budget donation across IPC. |
| Memory management | Model-based tests plus Miri; in-OS stress with poisoned freed pages. |
| Concurrency | loom on every lock-free structure and on the IPC fast path. A model has every place the code can take an event and drop it (an interrupt window in a loop), not only the place it waits for one: the idle watch's first model lacked its window and passed a protocol that lost wake-ups. A new model is run once against the mistake it exists to catch. |
| Syscall boundary | Coverage-guided fuzzer with a syscall grammar; invariant: kernel never panics, never leaks a capability, retyped Untyped memory always balances. |
| IDL protocols | Generated round-trip and version-skew tests; fuzz every server's decoder. |
| Filesystem | Differential test against an in-memory model; crash-consistency by cutting writes at every block boundary and remounting; image fuzzer; fsck must agree with the model. |
| Network | Interop against the host Linux stack over TAP for every protocol; TCP state machine against scripted packet traces; RFC conformance vectors for TLS and QUIC; packet fuzzer on every parser. |
| Drivers | virtio against QEMU's device models; NVMe, AHCI, xHCI, HDA and e1000e against QEMU emulation; a mock-device framework that replays recorded MMIO traces and injects faults. Each driver is also compared against a reference driver on the same device by register trace, and must benchmark at or better than it. Real hardware is M8 and needs a human. |
| Language targets | For each supported language: the generated bindings pass a shared conformance suite (same calls, same results as the Rust bindings); the language's own standard-library test suite runs on the OS with failures enumerated in a known-failures list per language, which may only shrink. |
| WASI | The official WASI test suite, vendored. |
| Graphics | Renderer output compared to `tiny-skia` reference with perceptual tolerance; compositor scenes captured by QEMU screendump and compared to goldens in `tests/golden/`. Review golden changes against the rendered output. |
| Desktop behavior | Scripted input over the QEMU monitor (keys, pointer), assert on the accessibility tree dump, not on pixels, wherever possible. |
| Published interfaces | The rustdoc of every repository builds with warnings denied (`test.sh`'s `docs` check): a broken link or an ambiguous name in the documentation a driver or application is written from fails the build like a compiler error. The documentation's sufficiency is tested by writing from it alone: the NVMe driver was. |
| Local console | Scripted keys over the QEMU monitor drive the shell (`run_console`): its answers on the serial line, the screen's rows of text in a screendump, both drivers restarted under it, the machine off on `shutdown`. |
| Boot | Boot under OVMF with Secure Boot on and off, with 1/2/8/64 vCPUs, 256 MB and 16 GB RAM. |
| Device faults | `inject=<driver>:<fault>@<n>` commits a device's fault (garbage completion, a request never seen, a spurious interrupt, a missed one, a device reset) inside the driver's first run (`run_faults`, every block driver, every fault): the client's checks all pass and nothing outside the driver reports an error. A mock-device framework replaying recorded register traces is still owed for faults QEMU's models cannot be made to commit (a device that writes outside a request's buffer, DMA after reset). |
| Reliability | Kill each driver and each restartable server under load; assert recovery inside a deadline and no data loss on committed writes. |
| Driver confinement | A hostile driver in the real driver's place (`virtio-rogue`, started by the device manager with exactly a driver's capabilities): it claims another device and another device's interrupt, has its device write and read memory it never mapped and write memory mapped read-only, asks for physical addresses, and writes configuration space. Each must fail as designed and the system must still boot. Evidence is taken from who enforces the boundary: the kernel's line for each refused access, never the device's own report (QEMU's virtio-blk completes with success a write the IOMMU refused: the data went nowhere and the status says OK). |

## 4. Performance and size gates

### 4.1 How a number becomes a gate

A gate is only worth having if it measures what it claims, on a fair comparison, with less noise than the change
it is meant to catch. These rules apply to every gate below.

- **Same host, same session.** Silica and the Linux baseline are measured on the same machine in the same run,
  interleaved (A, B, A, B). A baseline recorded on another host or another day is not comparable.
- **A pinned, reproducible, well-tuned Linux.** The baseline's kernel version, config and init live in the `os`
  repository and the tool builds the image from them. The config is tuned for the same job as the Silica image
  (virtio only, nothing loaded that the workload does not use), so Silica is compared with Linux at its best.
- **Timing gates count only under KVM** on a quiet host with pinned vCPUs. Under TCG, timings are recorded and
  never gated, because emulated instruction cost says nothing about cache, TLB or mode-switch cost.
- **Deterministic gates for fixed paths.** IPC, syscall entry and exit, context switch and page-fault delivery are
  also gated by instruction count (QEMU `-icount`, or hardware counters). The count has no noise, so any increase
  fails until the commit that causes it explains it. The count of one benchmark is the difference between a boot
  that runs it twice and a boot that runs it once, so boot work cancels out exactly.
- **Profiles are part of the instrument.** `tools/profile.sh` attributes a benchmark's kernel instructions (TCG
  with icount) or its processor cycles (KVM, the host's `perf` sampling the guest) to functions and source lines.
  A regression is explained with a profile of both commits, not by reasoning about the diff.
- **Enough samples, and the spread reported.** A micro-benchmark runs at least 10,000 iterations in the guest and
  reports minimum, median and p99. A boot-level metric takes at least 10 boots. Results carry their dispersion.
- **Ratchets.** Each metric keeps its best recorded result in the repository (`os/bench/ratchet.tsv`): the ratio to
  Linux measured in the same session, which carries from one host to another, or the value itself where Linux has
  no equivalent. A regression is a result worse than that best by more than the measured noise (three median
  absolute deviations, of both systems for a ratio, and for a timing at least 1%, which is how closely a timing
  repeats from one session to the next on the reference host), so slow creep cannot pass, and an improvement moves
  the ceiling down. A metric with no meaningful Linux equivalent is gated by its ratchet alone. A ratchet moves the
  other way only for a cost the system chose to pay, shown by benchmarking the kernel before and after the change in
  one session on one host, with both results written beside the new value in the spec section that owns the cost.
- **The host is held still.** `tools/bench.sh` puts the measured processors on the `performance` governor, switches off
  idle states slower than 20 us on them and turbo on the machine, for both systems, and restores what it found. Left
  on its power-saving default the host measured itself: turbo gave a core 5.2 or 4.9 GHz depending on how many others
  were awake, so one kernel read a null system call at 53 ns in one boot and 55 ns in the next (84 ns in five boots of
  five once held), and a quiet Silica guest got a faster core than a Linux guest with its housekeeping, which flattered
  every ratio: the page fault read 6% ahead of Linux and is 2.5% behind at one frequency. Deep idle states were most
  of the timer overshoot (p99 83 us to about 9 us; Linux 135 to 28). Absolute timings are therefore at the processor's
  base frequency; a result from a host that could not be held (no privilege) says so and records no ratchet. Values
  from the held host are a host of their own (`+tuned`); the ratios recorded before were restarted, the instruction
  counts kept. The two timer metrics still move 20 to 35% between sessions of one kernel (they are the host waking a
  virtual processor), so their ratchets allow that much and the same-session gate against Linux is what holds them;
  to compare two kernels on them, interleave their boots.
- **What the held host found.** The page fault was 2.5% behind a Linux minor fault (821 ns against 801). A third of
  it was not Silica's path at all: the first write to a freshly mapped page took 620 timestamp ticks where the next
  cache line took 6, because the kernel wrote page-table entries with the accessed and dirty bits clear and the
  processor set them itself, by microcode assist, on first use. Entries now carry both from the start (as Linux
  writes them): 569 ns against 804, ratio 0.71. Two hypotheses were measured and discarded on the way: saving and
  restoring the faulting thread's vector state (skipping it changed nothing), and exits to the hypervisor (none per
  fault). The instruction count went from 2761 to 2765: each of the fault's two hand-offs now tests whether another
  processor woke a thread meanwhile, without which that wake could be dropped. It is 2766.3 with the idle watch: the
  shoot-down's kick now tries a poke before an interrupt, one instruction more on the path that does neither
  (measured per function, `shoot_down` 104.00 to 105.00; the time is unchanged at 569 ns). That one instruction was
  first reported as three: the count is the difference of two boots, a boot varies by up to 4,000 instructions with
  the other processor's timing, and one benchmark is only 2,048 faults. The second boot now runs four more
  benchmarks than the first (0.1 per fault between repeats: 2765.29, 2765.33, 2765.33 before the watch and 2766.37,
  2766.23, 2766.30 after, interleaved), and the page fault's tolerance is one instruction like the other counts',
  no longer two.
- **Variants side by side.** `tools/bench.sh --compare <commit>` runs the kernel at that commit and the working tree,
  and `--sweep NAME=v1,v2,...` runs the working tree built once per value of a build-time constant
  (`kernel_core::tuned`, read from `SILICA_TUNE_<NAME>`; an ordinary build has plain constants), with their boots
  interleaved on the held host. This is how a constant gets its value and how a change is shown to have paid: the
  table goes beside the number it justified. It is an instrument; it gates and records nothing. First use: how long an
  idle processor watches for work before it halts (`IDLE_WATCH_NS`, ARCHITECTURE.md, Time).
- **Confinement is compared with confinement.** The benchmark machine has an IOMMU (Intel VT-d) and Silica always confines device DMA with one; QEMU emulates every translation in software, which no hardware does. So each comparison runs on the machine that makes it fair, and the harshest one for Silica wins a tie: kernel paths and boot compare Silica as it runs (confined) with Linux at its fastest, on the machine without an IOMMU; the block path compares both on the machine without an IOMMU (`blk_*`), and both confining DMA on the machine with one (`blk_*_confined`, Linux with `intel_iommu=on` in its fastest, lazy mode, where a freed buffer stays reachable for a while). Found the first time the block path was measured, against a baseline that turned out to lack MSI (below): Silica confined against Linux unconfined lost 15% at depth 32, all of it the emulator translating Silica's DMA. With the baseline corrected, in one held session (`bench.sh`, 5 runs): unconfined, Linux reads 4 KiB at depth 1 in 15.4 us against Silica's 16.5 (p99 18.0 against 23.2) and they tie at depth 32 (294,000 a second); confined, Silica leads, 17.6 against 19.9 us (p99 24.8 against 46.4) and 251,000 against 142,000 a second, because Linux maps and unmaps each request in the IOMMU and Silica maps a client's memory once, when it is registered. The unconfined depth-1 gap is Silica's extra hop (the device's interrupt reaches the driver's thread, which then wakes the client's; Linux completes in interrupt context and wakes the reader directly) and is open.
- **The baseline's configuration is checked.** `build_linux` fails when kconfig drops an option the baseline asks for: tinyconfig leaves out `CONFIG_PCI_MSI`, merge_config dropped it silently, and for its first block measurements the baseline's disk interrupted through a legacy wire and its IOMMU option was gone with it.
- **Linux is given the same technique.** When Silica gains one that Linux has as an option, the baseline turns it on:
  the baseline now idles with `cpuidle-haltpoll` (forced on, Linux's own adaptive poll time), which took its
  cross-processor round trips from 165,000 to 400,000 a second on one pair.
- **One machine so far.** Every timing recorded here is from one Intel desktop processor (i9-12900K, performance
  cores) under KVM. aarch64 has run only under emulation, where timings mean nothing, and nothing has run on bare
  metal or on AMD. "Faster than Linux" is shown for that machine and no other until the same session is run on a
  second x86 vendor, on real aarch64 and without a hypervisor; a constant chosen by a sweep (the idle watch) is
  re-swept there or replaced by a boot-time measurement.
- **A factor is not a throughput.** `ipc_cross_scaling` (four pairs over one) went from 4.5 to 3.8 when the idle
  watch made one pair 4.8 times faster and four pairs 4.1 times: both throughputs rose, and a factor above 4 had only
  ever meant that one pair was slow. Its ratchet was set to the new value; the throughputs carry the gate.
- **Same payload, same statistics.** The Silica and Linux benchmark programs (`kernel/roottest` bench mode and
  `os/bench/linux/init.c`) send the same bytes, take the same number of samples after the same warm-up, and report
  the same minimum, median and 99th percentile. Each system does what its own ABI requires for the program to
  continue correctly: Linux preserves vector registers across a system call, Silica does not. The Linux program
  is tuned as a latency-sensitive program would be (for timers: no timer slack).
- **Throughput is compared, not scaling.** A scaling factor (8 pairs over 1 pair) compares a system with itself:
  it is gated by its own floor, while the throughputs it is made of are each gated against Linux.
- **Observed from the host wherever possible.** Boot times are stamped by the host from the firmware starting the
  boot option to the ready marker: the firmware before that is the same code for both systems and moves by tens of
  milliseconds from boot to boot, more than an operating system's own boot takes, so it is reported beside the
  result and not gated. Memory is the pages the guest touched. Lost writes are verified by the host
  reading the disk image. Idle wakeups are vCPU exits. A guest's own report is used only for what the host cannot
  see.
- **Efficiency where emulation hides throughput.** Under QEMU the host bounds I/O throughput for both systems, so
  I/O gates measure guest CPU time per operation at a fixed rate; raw throughput is recorded.
- **A gate must be able to fail.** Each gate has a test that plants a regression and sees the gate fail. A metric
  that is missing at its milestone fails. A check on something that does not exist yet reports SKIP, never pass. A
  result that exists and misses its gate (slower than Linux, over its budget, worse than its ratchet) fails at every
  milestone: the milestone column says when a metric must exist, never when it may lose.
- **Real hardware has the last word.** Every gate is measured again on the reference machines at M8.

### 4.2 Gates

The numeric limits below were set by judgment before anything could be measured. The first real measurement of
each either confirms it or replaces it, with the measurement recorded beside the new number, and from then on the
ratchet holds it.

Kernel paths:

| Metric | Gate | From |
| --- | --- | --- |
| IPC round trip, same core, between two address spaces | under half a Linux `pipe` ping-pong; instruction count ratchet | M2 |
| Null system call | at or below Linux `getppid`; instruction count ratchet | M2 |
| IPC round trip, cross core, and with one capability transferred | at or below Linux (pipe ping-pong across cores); instruction count ratchet | M2 |
| IPC throughput, 8 independent pairs on 8 cores | at least 7x one pair | M2 |
| Context switch between address spaces, FPU state live | at or below Linux; instruction count ratchet | M2 |
| Page fault resolved by a userspace pager | at or below a Linux minor fault; instruction count ratchet | M2 |
| Process spawn to the child's first instruction | faster than Linux `fork`+`exec` of a static binary | M3 |
| Empty process: kernel objects plus runtime, in bytes | ratchet | M2 |
| Timer: sleep overshoot p99 | at or below Linux | M2 |
| Scheduling latency under the defined load, p99.9 and maximum over 10 minutes | at or below Linux | M3 |

Whole operations, which carry the cost a microkernel adds between servers:

No gate permits Silica to be slower than Linux, at any milestone. A path that cannot match Linux when it is first
built shows that the architecture under it is wrong, and that is cheapest to fix before anything is built on it; a
gate that let it through would defer the discovery to a rewrite. Every gate is also a ratchet.

| Metric | Gate | From |
| --- | --- | --- |
| Open, read 4 KiB, close, through application, filesystem, block server and driver | at or below Linux | M5 |
| 4 KiB write plus sync, p99 | at or below Linux | M5 |
| Small-file metadata throughput | at or above Linux | M5 |
| Block I/O: guest CPU per operation at a fixed rate, virtio-blk from M3, NVMe from the milestone its driver lands | at or below Linux, each against the same device | M3 |
| Block I/O: 4 KiB direct reads at depth 1 (median and p99) and depth 32 (throughput), unconfined and confined (`blk_read4k_*`) | at or better than Linux (`O_DIRECT` pread, io_uring at depth 32) | M3 |
| Network: a 60-byte frame's round trip to the host (median and p99) and 1514-byte frames sent a second, unconfined and confined (`net_rtt*`, `net_tx*`) | at or better than Linux: raw frames through AF_PACKET (blocking send and receive; `sendmmsg` past the queueing discipline) and AF_XDP (zero-copy on virtio-net), the faster of the two for transmit | M3 |
| HTTP request p99 latency at a fixed rate, 64 connections | at or below Linux | M4 |
| TCP: guest CPU per gigabyte at a fixed rate | at or below Linux | M4 |

System:

| Metric | Gate | From |
| --- | --- | --- |
| Boot to first userspace process | faster than Linux; ratchet | M2 |
| Boot to network-ready server | faster than Linux; ratchet | M4 |
| Idle memory, server image | at most 25% of the Linux baseline; ratchet in bytes | M4 |
| Idle wakeups over 60 s | 0 on the server image; 0 on the desktop with a static screen | M4, M6 |
| Memory and capability count after a 24 h soak | no growth | M4 |
| Driver crash recovery: kill virtio-blk and virtio-net during sustained I/O | service resumes within 250 ms; zero committed writes lost, verified by the host; open connections continue. Linux forced-unbind result recorded | M3 |
| Clock: drift against the host over 1 h; monotonic time never steps back across CPUs or suspend | within the NTP bound; zero backward steps | M4 |

Desktop:

| Metric | Gate | From |
| --- | --- | --- |
| Input to frame | at most one frame | M6 |
| Dropped frames over 60 s of the reference scene | 0 | M6 |
| Audio underruns over 10 minutes with a 10 ms buffer under the defined load | 0 | M6 |
| Cold start of a native app | faster than Linux | M6 |

### 4.3 Size

Budgets are in `spec/ARCHITECTURE.md` section 2 and `tools/test.sh --fast` checks them. The same rules of
measurement apply:

- Measure every architecture that builds, and include `.data` and `.bss` beside text and rodata.
- Count the vendored crates the kernel links in its line ceiling.
- Count kernel operations, meaning every syscall and every invocation label of every object type, so one
  multiplexed syscall cannot hide a wide interface.
- Resident text of the core servers is measured from the running image.

### 4.4 Fuzzing

A fuzzer that runs clean for ten minutes proves little if it reaches a tenth of the code. A fuzz gate states the
coverage it reached on the target, keeps its corpus, and fails when coverage drops. The corpus is committed beside
the target, minimized (`<crate>/fuzz/corpus/<target>`), and the floor is the coverage libFuzzer reports on loading
it (`<crate>/fuzz/coverage-floor.tsv`): a number that does not depend on time or luck, checked before every run,
so a fresh clone gates exactly what a long-lived workstation does. `tools/fuzz.sh --save` updates both; a floor goes
down only in a commit that says why. `tools/test.sh --deep` fuzzes each target for ten minutes.
