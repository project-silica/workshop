# Testing Silica

`tools/test.sh` checks the integrated build. `--fast` (default): lint, host tests, target builds, a boot and the
system image's guest tests. `--full`: adds every guest test on both architectures, the boot matrix, Miri, loom and
the tools' own tests. `--deep`: adds fuzzing, the benchmarks and the Kani proofs. `--plan` says what would run and
why; `--fresh` holds nothing; `--guest NAME` runs one guest test; `--repo X` limits the scope.

## 1. What finished means

A change is finished when the integrated image boots with it, a test exercises it through the interface a real
caller uses, its failure path says what failed and why, and its cost is measured.

- **Trust boundaries hold.** Nothing a less trusted party sends can crash, hang or confuse a more trusted one: the
  kernel any syscall argument, a server any message, a driver any device, a parser any bytes. Every boundary has its
  promise written beside the code and an attack test that fails when the promise breaks (ARCHITECTURE.md,
  Invariants); show the test failing on the code before the fix.
- **Committed data survives** power cuts, crashes, killed drivers and failed updates.
- **Every failure is handled and explained**, in terms the caller or owner can act on. Running out of memory, queue
  space or capabilities is an error returned to the caller.
- **It behaves at the edges:** sustained load, 64 CPUs, 256 MB of RAM, a full disk, a device gone mid-request,
  suspend and resume, a component killed and restarted.
- **Timing comes from the hardware or the protocol,** never from a delay tuned until a test passed.
- **Authority is minimal and visible.**
- **Interfaces say what they mean:** who owns each buffer and capability, what each error means, what ordering is
  required and what happens on reset, generated from the source.
- **Results repeat:** builds are reproducible (`tools/repro.sh --system` builds twice in different directories and
  locales), tests are deterministic, and a performance claim comes with the command that reproduces it.
  `tools/check-protocols.sh` checks every published protocol against the shipped definitions.

Tests verify correctness; they do not define the solution. Code that passes by special-casing a test's inputs is
wrong; a wrong test is fixed and the fix explained.

## 2. What runs, and when

A check is a function of its inputs and is not run twice on the same ones: a unit that passed on exactly its inputs
is read back from the evidence store (`target/evidence` of the main workshop, shared by worktrees; `tools/lib/evidence.sh`),
and a failure is never stored. A change runs what it can affect; nobody chooses a subset by hand. Checks that judge
logic run at once; a check that judges a time says so (`quiet` in the kernel's test manifest, `QUIET_SYSTEM` in
`tools/test.sh`) and runs alone first.

| When | Run |
| --- | --- |
| While changing something | the one test that exercises it: `--guest NAME`, or `cargo test -p <crate> <name>` |
| Before a commit | `tools/test.sh --fast` (under a minute with nothing held: `tools/tests/fast_budget.sh`) |
| Before `tools/pin.sh` | `tools/test.sh --full` |
| After changing a parser, a decoder or another trust boundary | `tools/fuzz.sh --repo <repo>` (ten minutes a target) |
| After changing a measured path | `tools/bench.sh --only insns` first, then `tools/bench.sh` if a timing is in question |
| Choosing between designs | `tools/bench.sh --compare A,B,C` |
| Declaring a milestone | `SILICA_MILESTONE=<n> tools/test.sh --deep --fresh` |

A result that depends on timing is found by running that test by name, many times, under load; a race is fixed
where it is. A red result is information once: fix it or record its cause where the next run shows it. A result
suspected of being noise is a defect of the instrument, and the instrument is what gets fixed.

## 3. Oracles by layer

| Layer | Oracle |
| --- | --- |
| Kernel objects, caps, IPC | A reference model compared after each step of random sequences; Kani for a capability copy; exhaustive revoke over bounded derivation lists (`exhaustive.rs`); `hostile.rs` attacks every rights check. The proof obligations still open are in MILESTONES.md. |
| Scheduler | Deterministic host simulation: fairness bounds, deadline admission, no starvation, donation across IPC, a program's share independent of its thread count. |
| Memory management | Model-based tests plus Miri; in-OS stress with poisoned freed pages. |
| Concurrency | loom on every lock-free structure and the IPC fast path, with every place an event can be dropped modelled; a new model is run once against the mistake it catches. |
| Syscall boundary | A grammar fuzzer: the kernel never panics, never leaks a capability, Untyped always balances. |
| IDL protocols | Generated round-trip, version-skew and known-answer tests; every server's decoder fuzzed. |
| Filesystem | Differential test against an in-memory model; crash consistency by cutting writes at every block boundary; image fuzzer. |
| Network | Interop against the host's Linux stack over a tap, including hostile peers; scripted packet traces; RFC vectors; a fuzzer on every parser. |
| Drivers | QEMU device models; fault injection (`inject=`, `run_faults`); comparison with a reference driver by register trace and benchmark. Real hardware is M8. |
| Driver confinement | A hostile driver with exactly a driver's capabilities (`virtio-rogue`): every attempt beyond them fails, judged by the component that enforces the boundary. |
| Reliability | Every driver and restartable service killed under load: recovery inside its deadline, no committed write lost. |
| Language targets | Generated bindings pass a shared conformance suite; each language's own test suite with a known-failures list that only shrinks. WASI's official suite. |
| Graphics, desktop | Renderer against `tiny-skia` with perceptual tolerance; screendumps against goldens; scripted input asserting on the accessibility tree. |
| Published interfaces | Rustdoc with warnings denied; documentation tested by writing a driver or app from it alone. |
| Boot | OVMF with Secure Boot on and off; 1/2/8/64 vCPUs; 256 MB and 16 GB. |

## 4. Performance and size gates

### 4.1 How a number becomes a gate

- **The aim is each path's own best.** A path is tuned against Silica's best result until a profile shows that what
  remains is work the hardware or a guarantee requires; every improvement becomes the new ratchet. A performance
  change is finished when its profile shows no removable cost left, and its commit records the profile and what was
  tried.
- **Linux is a floor, not a finish line.** Its numbers are in `os/bench/reference.tsv` and are final; every boot of
  a run is Silica's, and `bench.sh` judges each metric with a Linux number against it as it does today. Linux is
  booted only to give a new metric its number, once (`bench.sh --linux`). A metric with no Linux equivalent is held
  by its ratchet.
- **Silica is measured once per state of its sources,** in groups (kernel paths, devices, server) kept under their
  inputs.
- **Timings are taken on a held host doing nothing else** (performance governor, shallow idle states, turbo off,
  processors pinned), and the run reports how true that was. Timed boots take the machine over and are not started
  while someone uses its desktop. Timing gates count only under KVM.
- **Instruction counts gate fixed paths** (IPC, syscall entry, context switch, page fault): exact, taken as the
  difference of two boots, counted once per kernel source. Any increase is explained by a profile of both commits
  (`tools/profile.sh`).
- **Samples and spread:** at least 10,000 iterations for a micro-benchmark, 10 boots for a boot metric; medians,
  minimums and p99 with their dispersion.
- **Ratchets** (`os/bench/ratchet.tsv`): each metric's best result; worse than it by more than the noise (three
  median absolute deviations, at least 1% for a timing) is a regression.
- **A known gap is recorded and can only shrink.** `os/bench/open.tsv` holds each known shortfall (the metric,
  `linux` or `ratchet`, the bound it may not pass, the host, and why), added by a commit that says why. While no
  worse than its bound the run reports it OPEN; past it, an error. `--update-ratchet` tightens or removes lines;
  nothing loosens one. When a guarantee costs speed, its cost is recorded there with the guarantee it buys and won
  back in the design (ARCHITECTURE.md, Invariants 10). A milestone is not declared over an open gap of a metric it
  requires.
- **A gate must be able to fail:** each has a test that plants a regression; a missing metric fails at its milestone;
  a check on something that does not exist yet is a SKIP, never a pass.
- **Comparisons are fair:** the same payload and statistics on both systems (`kernel/roottest` bench mode and
  `os/bench/linux/init.c`), the same VM tuning, confinement compared with confinement, observed from the host where
  possible, guest CPU per operation where emulation bounds throughput.
- **Variants side by side:** `--compare` (commits, ranges, worktrees), `--sweep NAME=v1,v2`, `--aa` for a control,
  `--steps` to find the commit that cost something; counts first, timings interleaved in rotating order.
- **One machine so far** (i9-12900K under KVM); every gate is measured again on the reference machines at M8.

### 4.2 Gates

A gate that names Linux applies through the metric's number in `os/bench/reference.tsv`; a metric without one is
held by its ratchet from its first measurement. No gate permits Silica to be slower than Linux; every gate is also a
ratchet.

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

Whole operations:

| Metric | Gate | From |
| --- | --- | --- |
| Open, read 4 KiB, close, through application, filesystem, block server and driver | at or below Linux | M5 |
| 4 KiB write plus sync, p99 | at or below Linux | M5 |
| Small-file metadata throughput | at or above Linux | M5 |
| Block I/O: guest CPU per operation at a fixed rate, virtio-blk from M3, NVMe from its milestone | at or below Linux, same device | M3 |
| Block I/O: 4 KiB direct reads at depth 1 (median and p99) and depth 32 (throughput), unconfined and confined (`blk_read4k_*`) | at or better than Linux (`O_DIRECT` pread, io_uring at depth 32) | M3 |
| Network: a 60-byte frame's round trip (median and p99) and 1514-byte frames sent a second, unconfined and confined (`net_rtt*`, `net_tx*`) | at or better than Linux (AF_PACKET; AF_XDP zero-copy for transmit, the faster of the two) | M3 |
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
| Driver crash recovery: kill virtio-blk and virtio-net during sustained I/O | resumes within 250 ms; zero committed writes lost, verified by the host; connections continue | M3 |
| Clock: drift against the host over 1 h; monotonic time never steps back across CPUs or suspend | within the NTP bound; zero backward steps | M4 |

Desktop:

| Metric | Gate | From |
| --- | --- | --- |
| Input to frame | at most one frame | M6 |
| Dropped frames over 60 s of the reference scene | 0 | M6 |
| Audio underruns over 10 minutes with a 10 ms buffer under the defined load | 0 | M6 |
| Cold start of a native app | faster than Linux | M6 |

### 4.3 Size

Budgets are in `spec/ARCHITECTURE.md` section 2, checked by `tools/size.sh`. Measure every architecture that builds,
including `.data` and `.bss`; count vendored crates the kernel links; count every syscall and invocation label;
measure resident text of the core servers from the running image.

### 4.4 Fuzzing

Every trust boundary has a fuzz target that runs ten minutes clean (`tools/test.sh --deep` runs each). Each target
keeps a minimized corpus (`<crate>/fuzz/corpus/<target>`) and a coverage floor (`<crate>/fuzz/coverage-floor.tsv`):
the coverage libFuzzer reports on loading the corpus, checked before every run. `tools/fuzz.sh --save` updates both.
A floor never goes down: a change that removes coverage brings coverage of its own code to make it up.
