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
| Concurrency | loom on every lock-free structure and on the IPC fast path. |
| Syscall boundary | Coverage-guided fuzzer with a syscall grammar; invariant: kernel never panics, never leaks a capability, retyped Untyped memory always balances. |
| IDL protocols | Generated round-trip and version-skew tests; fuzz every server's decoder. |
| Filesystem | Differential test against an in-memory model; crash-consistency by cutting writes at every block boundary and remounting; image fuzzer; fsck must agree with the model. |
| Network | Interop against the host Linux stack over TAP for every protocol; TCP state machine against scripted packet traces; RFC conformance vectors for TLS and QUIC; packet fuzzer on every parser. |
| Drivers | virtio against QEMU's device models; NVMe, AHCI, xHCI, HDA and e1000e against QEMU emulation; a mock-device framework that replays recorded MMIO traces and injects faults. Each driver is also compared against a reference driver on the same device by register trace, and must benchmark within 10% of it. Real hardware is M8 and needs a human. |
| Language targets | For each supported language: the generated bindings pass a shared conformance suite (same calls, same results as the Rust bindings); the language's own standard-library test suite runs on the OS with failures enumerated in a known-failures list per language, which may only shrink. |
| WASI | The official WASI test suite, vendored. |
| Graphics | Renderer output compared to `tiny-skia` reference with perceptual tolerance; compositor scenes captured by QEMU screendump and compared to goldens in `tests/golden/`. Review golden changes against the rendered output. |
| Desktop behavior | Scripted input over the QEMU monitor (keys, pointer), assert on the accessibility tree dump, not on pixels, wherever possible. |
| Boot | Boot under OVMF with Secure Boot on and off, with 1/2/8/64 vCPUs, 256 MB and 16 GB RAM. |
| Reliability | Kill each driver and each restartable server under load; assert recovery inside a deadline and no data loss on committed writes. |

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
  fails until the commit that causes it explains it.
- **Enough samples, and the spread reported.** A micro-benchmark runs at least 10,000 iterations in the guest and
  reports minimum, median and p99. A boot-level metric takes at least 10 boots. Results carry their dispersion.
- **Ratchets.** Each metric keeps its best recorded result in the repository (`os/bench/ratchet.tsv`): the ratio to
  Linux measured in the same session, which carries from one host to another, or the value itself where Linux has
  no equivalent. A regression is a result worse than that best by more than the measured noise (three median
  absolute deviations, of both systems for a ratio), so slow creep cannot pass, and an improvement moves the
  ceiling down. A metric with no meaningful Linux equivalent is gated by its ratchet alone.
- **Same payload, same statistics.** The Silica and Linux benchmark programs (`kernel/roottest` bench mode and
  `os/bench/linux/init.c`) send the same bytes, take the same number of samples after the same warm-up, and report
  the same minimum, median and 99th percentile. Each system does what its own ABI requires for the program to
  continue correctly: Linux preserves vector registers across a system call, Silica does not.
- **Observed from the host wherever possible.** Boot times are stamped by the host between QEMU start, the first
  serial byte and the ready marker. Memory is the pages the guest touched. Lost writes are verified by the host
  reading the disk image. Idle wakeups are vCPU exits. A guest's own report is used only for what the host cannot
  see.
- **Efficiency where emulation hides throughput.** Under QEMU the host bounds I/O throughput for both systems, so
  I/O gates measure guest CPU time per operation at a fixed rate; raw throughput is recorded.
- **A gate must be able to fail.** Each gate has a test that plants a regression and sees the gate fail. A metric
  that is missing at its milestone fails. A check on something that does not exist yet reports SKIP, never pass.
- **Real hardware has the last word.** Every gate is measured again on the reference machines at M8.

### 4.2 Gates

The numeric limits below were set by judgment before anything could be measured. The first real measurement of
each either confirms it or replaces it, with the measurement recorded beside the new number, and from then on the
ratchet holds it.

Kernel paths:

| Metric | Gate | From |
| --- | --- | --- |
| IPC round trip, same core, between two address spaces | under half a Linux `pipe` ping-pong; instruction count ratchet | M2 |
| Null system call | at or below Linux `getppid`; ratchet | M2 |
| IPC round trip, cross core, and with one capability transferred | ratchet | M2 |
| IPC throughput, 8 independent pairs on 8 cores | at least 7x one pair | M2 |
| Context switch between address spaces, FPU state live | at or below Linux | M2 |
| Page fault resolved by a userspace pager | ratchet; Linux minor fault recorded | M2 |
| Process spawn to the child's first instruction | faster than Linux `fork`+`exec` of a static binary | M3 |
| Empty process: kernel objects plus runtime, in bytes | ratchet | M2 |
| Timer: sleep overshoot p99 | at or below Linux | M2 |
| Scheduling latency under the defined load, p99.9 and maximum over 10 minutes | at or below Linux | M3 |

Whole operations, which carry the cost a microkernel adds between servers:

A gate of the form "within Nx" is the floor for the milestone that introduces the path, and it permits Silica to be
slower than Linux. The destination does not: every one of these is also a ratchet, and the system is not finished
until each is at or better than Linux on the same hardware (`AGENTS.md`, commitment 5).

| Metric | Gate | From |
| --- | --- | --- |
| Open, read 4 KiB, close, through application, filesystem, block server and driver | within 1.5x of Linux | M5 |
| 4 KiB write plus sync, p99 | within 1.25x | M5 |
| Small-file metadata throughput | within 1.5x | M5 |
| Block I/O: guest CPU per operation at a fixed rate, virtio-blk from M3, NVMe from the milestone its driver lands | within 1.1x, each against the same device on Linux | M3 |
| HTTP request p99 latency at a fixed rate, 64 connections | at or below Linux | M4 |
| TCP: guest CPU per gigabyte at a fixed rate | within 1.25x | M4 |

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
