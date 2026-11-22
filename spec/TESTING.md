# Testing Silica

`tools/test.sh` checks the integrated build: `--fast` (the default) is lint, host tests, target builds, a boot and the system image's guest tests; `--full` adds every guest test on both architectures, the boot matrix, Miri, loom and the tools' own tests; `--deep` adds fuzzing, the benchmarks and the Kani proofs. A tier says what must hold. What runs is the part of it whose inputs changed since it last passed (section 2), at once where it can. `--plan` runs nothing and says what would run and why; `--fresh` holds nothing; `--guest NAME` runs one guest test, always; `--repo X` limits the scope. Additional guest tests are listed in `kernel/tests/inos-<architecture>.txt`, one name per line. The result and failure details are available under `target/logs/`.

Miri runs every kernel-core test in a process of its own, many at a time (built once; the same tests and flags as `cargo miri test`): run one after another they took 55 minutes of every full run, nearly all of it in the slowest few. A Miri run that finds no test is a failure, as is a test Miri stops without a result.

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

## 2. What runs, and when

Testing is paid for in the time it takes away from building, so each run has to buy something a previous run did
not already show. Two days of this project's logs, before this section existed, held 26 full runs (16.8 hours, the
same 35 to 85 minutes whether the change was one line of the shell or nothing at all), a two-hour deep run, and the
benchmark against Linux run seven times in one evening, every run red for the same known reasons and every run
booting Linux ten times to learn its numbers again. Most of that bought nothing: the answer was already known, and
the tools could not say so.

**A check is a function of its inputs, and is not run twice on the same ones.** Every check is a unit that names
what it depends on: the checkouts it builds (as they are now, uncommitted changes included), or one crate and what
it builds from, the harness functions that run it, the emulator and its firmware, the variables that change what it
does (`tools/lib/evidence.sh`). A unit that passed on exactly these inputs is read back from the store
(`target/evidence` of the main workshop, shared by every worktree: the key is content, not place) and one whose
inputs changed runs. A failure is never stored. So:

- A second run of an unchanged tree takes seconds at any tier, in any worktree, in any later session. What the
  last session showed does not have to be shown again to be believed: the commit says what ran, and the store
  holds it.
- A change runs what it can affect. The shell's source is no input of the kernel's Miri run, its loom models, its
  guest tests or the tools' own tests; kernel-core is an input of nearly everything. Nobody chooses a subset by
  hand, and nothing is skipped by judgment.
- `tools/test.sh --plan --full` says what a tier would run now, how long that took the last time and which input
  changed, before anything is spent.
- What does run, runs at once, where running at once cannot change the answer. A check that judges logic (does
  the call return the documented error, does the driver recover, does the model agree) gives the same answer
  beside thirty others: every guest boot assembles its own image from one build of the run's sources, the
  repositories' host suites run side by side, Miri and the tools' own tests run beside the guests. A check that
  judges a time does not. The first full run made at once failed the kernel's `sched` test on both architectures
  ("a waking thread waited behind busy ones for more than 2 ms"): the kernel had not changed, the host had thirty
  guests on it. So a check that judges a time says so (`quiet` on its line of the kernel's test manifest;
  `QUIET_SYSTEM` in `tools/test.sh` for the two recovery deadlines) and those run first, one at a time, with the
  host to themselves; then everything else at once. A full run with nothing held went from 35 minutes to
  13 (428 checks), and Miri is all of it past the fifth minute: seven of its tests, each a replayed system-call
  sequence, take ten minutes apiece under the interpreter, and making those cheaper is the next thing to do here.

**When each tier is the right one.**

| When | Run | Why that much |
| --- | --- | --- |
| Starting a session | `tools/test.sh --fast`, then `tools/test.sh --plan --full` | The first is held, or under a minute. The second runs nothing and says what the tree still owes: that is run before the next pin, not before the first line of code. |
| While changing something | the one test that exercises it: `--guest NAME`, or `cargo test -p <crate> <name>` | The loop that finds the bug is seconds long. |
| Before a commit | `tools/test.sh --fast` | Under a minute with nothing held (`tools/tests/fast_budget.sh` keeps it there). |
| Before `tools/pin.sh` | `tools/test.sh --full` | Runs what the commits since the last pin can affect. |
| After changing a parser, a decoder or another trust boundary | `tools/fuzz.sh --repo <repo>` | Ten minutes a target, for the repository that changed. |
| After changing a measured path | `tools/bench.sh --only insns` first, then `tools/bench.sh` if a timing is in question (section 4.1) | Counts are exact and disturb nobody. A timed run boots only the group the change belongs to, never Linux. |
| Choosing between designs | `tools/bench.sh --compare A,B,C` | Every candidate in one run. |
| Declaring a milestone | `SILICA_MILESTONE=<n> tools/test.sh --deep --fresh` | Nothing held, Silica measured again, no open gap due. |

**What the store cannot see, and what covers it.**

- *A result that depends on timing.* A test with a race passes once and is then held. Running everything again and
  hoping is not how such a test is found: it is run by name, many times (`--guest NAME` always runs), under load,
  and the race is fixed where it is. A unit known to judge a time runs when the host does nothing else.
- *An input nobody named.* Units name repositories whole unless a narrower input is certainly right (Miri: the
  crate and what it builds from). `tools/tests/evidence.sh` shows each rule both ways: held on the same inputs, run
  on a changed tracked file, untracked file, dependency, harness function, variable or emulator.
- *The store itself.* A hosted run starts from a fresh clone and an empty store, and a milestone is declared from
  `--fresh`: every check of the exit test ran on that tree, on that day.

**Running it again is not a method.** A red result is information once. It is fixed, or its cause is named and
recorded where the next run will show it (a failing test that says what is missing; for a measurement, an open
gap: section 4.1), and work goes on. A result suspected of being noise is a defect of the instrument, and the
instrument is what gets fixed: the gate's noise allowance, the host's stillness, the sample count.

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

- **Linux is locked.** Linux is the yardstick, not what is being built, and its numbers on a given host do not
  change. They are written down once, in `os/bench/reference.tsv` (per metric: Linux at its best, its best session
  median, over the clean sessions of 2026-11-22 on the reference host: eight sessions of five boots for the kernel
  paths, two for boot and the devices), and `tools/bench.sh` compares Silica with that file. No run boots Linux.
  Silica's target on every metric with a Linux equivalent is **15% better than the locked number** (a ratio of at
  most 0.85; a metric whose own limit is stricter, such as the IPC round trip at half, keeps it). The margin is
  what makes the lock sound: across those sessions Linux's medians moved by 1 to 4% (its 99th percentiles by up to
  16%), so a result at its target is ahead of Linux by more than Linux moves, and nothing has to be measured again
  to say so. It also sets the direction: matching Linux is not the goal. Before this rule every session booted
  Linux ten times (60% of its timed boots) to learn the same numbers again, and two sessions disagreed about
  Linux by more than Silica had changed. Linux has been measured and is not measured again, for any metric or
  reason: a metric with no number in the file is gated by its ratchet alone.
- **Silica is measured once per state of its sources**, in two groups with their own boots (the kernel paths; the
  devices), each kept under what it is a function of (`tools/lib/evidence.sh`: the sources, the image, the
  emulator, the host, the function that boots the machine). A change to a driver boots the system image and
  nothing else, and a tree that did not change boots nothing: the results are printed from what was measured, and
  the run says from when.
- **A timing is taken on a host doing nothing else, and the run says how true that was.** `bench.sh` measures
  what other programs did while its timed boots ran (the machine's busy time less its own) and prints it with the
  results. Found the first time it was looked at: a stray process of the tools' own author spinning for an hour on
  one of the eight measured cores. The single-processor paths read the same as ever; Linux's own eight-pair
  throughput read 4.5% and then 11.8% under its locked number, which is how the session was known to be spoiled.
  Timed boots take the machine over (turbo off, eight processors busy, a real-time echo on a ninth), so with
  someone at its desktop they are not started unless `--now` says to; instruction counts disturb nobody and always run.
- **A pinned, reproducible, well-tuned Linux.** The baseline's kernel version, config and init live in the `os`
  repository and the tool builds the image from them. The config is tuned for the same job as the Silica image
  (virtio only, nothing loaded that the workload does not use), so Silica is compared with Linux at its best.
- **Timing gates count only under KVM** on a quiet host with pinned vCPUs. Under TCG, timings are recorded and
  never gated, because emulated instruction cost says nothing about cache, TLB or mode-switch cost.
- **Deterministic gates for fixed paths.** IPC, syscall entry and exit, context switch and page-fault delivery are
  also gated by instruction count (QEMU `-icount`, or hardware counters). The count has no noise, so any increase
  fails until the commit that causes it explains it. The count of one benchmark is the difference between a boot
  that runs it twice and a boot that runs it once, so boot work cancels out exactly. A count is a property of the
  kernel's source: it is taken when that changes, its eight emulated boots at once (they were seven of a run's
  eleven minutes, one after another, on every run).
- **Profiles are part of the instrument.** `tools/profile.sh` attributes a benchmark's kernel instructions (TCG
  with icount) or its processor cycles (KVM, the host's `perf` sampling the guest) to functions and source lines.
  A regression is explained with a profile of both commits, not by reasoning about the diff.
- **Enough samples, and the spread reported.** A micro-benchmark runs at least 10,000 iterations in the guest and
  reports minimum, median and p99. A boot-level metric takes at least 10 boots. Results carry their dispersion.
- **Ratchets.** Each metric keeps its best recorded result in the repository (`os/bench/ratchet.tsv`): its best
  value on the host that measured it and its best ratio to Linux's locked number, or the value alone where Linux
  has no equivalent. A regression is a result worse than that best by more than the measured noise (three median
  absolute deviations, of both systems for a ratio, and for a timing at least 1%, which is how closely a timing
  repeats from one session to the next on the reference host), so slow creep cannot pass, and an improvement moves
  the ceiling down. A metric with no meaningful Linux equivalent is gated by its ratchet alone. A ratchet moves the
  other way only for a cost the system chose to pay, shown by benchmarking the kernel before and after the change in
  one session on one host, with both results written beside the new value in the spec section that owns the cost.
- **At the target is what the runs cannot tell from the target.** A gate fails when the ratio is past its limit by
  more than the noise of Silica's runs (three deviations). Judged to the last digit, a result at its limit passes
  and fails by turns, and a gate that fails by turns is run again until it passes, which is the most expensive way
  there is to learn nothing.
- **A known gap is recorded, and then it can only shrink.** A gate that fails on every run for a reason already
  known stops being read: the benchmark was red for days for the block path's depth-1 tail and for ratchets nobody
  had settled, and a new regression would have been one more red line among nine. A shortfall that is known and not
  yet closed is a line in `os/bench/open.tsv` (the metric, whether it is behind Linux or behind its own ratchet,
  the bound it is recorded at, why), added by a commit that says why. While the metric is no worse than its bound
  the run reports it as OPEN and passes, so the run's status says whether anything got worse; past the bound it is
  an error again. Every run lists the open gaps. `--update-ratchet` tightens a bound that improved and removes a
  gap that closed, and nothing in the tools adds or loosens one. A milestone is not declared over an open gap of
  a metric it requires (`SILICA_MILESTONE=<n>` makes each an error). One focused attempt at a gap (a profile of
  both systems, a design change measured with `--compare`) either closes it or ends in a line here and a
  paragraph in the section that owns the path saying what was learned; the work then goes on, and the gap is
  closed before the milestone is.
- **Linux is the yardstick, not the product.** The baseline's kernel, config, benchmark program and virtual
  machine were corrected twice before the numbers were locked (MSI, and idle polling) and do not change again,
  least of all to explain a gap: a gap is closed in Silica, or recorded. What pushes Silica on is its own ratchet: every improvement becomes the floor, at 15% past
  Linux as anywhere else, until a path has nothing left to give.
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
- **Variants side by side, as many as there are candidates.** `tools/bench.sh --compare <kernel>[,<kernel>...]`
  measures each named kernel (a commit, every commit of a range `a..b`, or another worktree's checkout: another
  design) and the working tree in one run, and `--sweep NAME=v1,v2,...` the working tree built once per value of a
  build-time constant (`kernel_core::tuned`, read from `SILICA_TUNE_<NAME>`; an ordinary build has plain
  constants). This is how a constant gets its value, how one of several designs is chosen, how a change is shown
  to have paid and how the commit that cost something is found: the table goes beside the number it justified. It
  is an instrument; it gates nothing. What keeps seven variants as clean as two:
  - *Counts first.* An instruction count is emulated and exact, so nothing one boot does reaches another: every
    variant's counts are taken at the same time, on all the host's processors, and kept per kernel source, so a
    commit is counted once in its life. Seven kernels cost what one does (`--only insns` asks nothing else and
    holds no host). For a change to a fixed path this is the first question and usually the last: a path that
    executes the same instructions was not changed by the change.
  - *Timings one at a time, in rotation.* Two timed guests on one host share its caches and memory, so timings are
    never taken together. The variants' boots are interleaved on the held host in an order that rotates every round
    (A B C, then B C A, then C A B), so what the host does meanwhile, and whatever one boot leaves behind for the
    next, falls on every variant alike.
  - *An A/A control.* `--aa` measures the reference a second time as a variant of its own. What that column
    reports as a change is what the instrument reports when nothing changed; a difference between real variants no
    larger than it is not a difference.
  - *Steps.* `--steps` shows each column's change from the one before it instead of from the first: over a range of
    commits, the one that cost something is the column that says so.
  First use: how long an idle processor watches for work before it halts (`IDLE_WATCH_NS`, ARCHITECTURE.md, Time).
  Owed its second: the two instruction-count gaps in `os/bench/open.tsv`, which
  `bench.sh --compare 6f6c470..HEAD --only insns --steps` assigns to their commits.
- **Confinement is compared with confinement.** The benchmark machine has an IOMMU (Intel VT-d) and Silica always confines device DMA with one; QEMU emulates every translation in software, which no hardware does. So each comparison runs on the machine that makes it fair, and the harshest one for Silica wins a tie: kernel paths and boot compare Silica as it runs (confined) with Linux at its fastest, on the machine without an IOMMU; the block path compares both on the machine without an IOMMU (`blk_*`), and both confining DMA on the machine with one (`blk_*_confined`, Linux with `intel_iommu=on` in its fastest, lazy mode, where a freed buffer stays reachable for a while). Found the first time the block path was measured, against a baseline that turned out to lack MSI (below): Silica confined against Linux unconfined lost 15% at depth 32, all of it the emulator translating Silica's DMA. With the baseline corrected, in one held session (`bench.sh`, 5 runs): unconfined, Linux reads 4 KiB at depth 1 in 15.4 us against Silica's 16.5 (p99 18.0 against 23.2) and they tie at depth 32 (294,000 a second); confined, Silica leads, 17.6 against 19.9 us (p99 24.8 against 46.4) and 251,000 against 142,000 a second, because Linux maps and unmaps each request in the IOMMU and Silica maps a client's memory once, when it is registered. The unconfined depth-1 gap is Silica's extra hop (the device's interrupt reaches the driver's thread, which then wakes the client's; Linux completes in interrupt context and wakes the reader directly) and is open.
- **The baseline's configuration is checked.** `build_linux` fails when kconfig drops an option the baseline asks for: tinyconfig leaves out `CONFIG_PCI_MSI`, merge_config dropped it silently, and for its first block measurements the baseline's disk interrupted through a legacy wire and its IOMMU option was gone with it.
- **Linux was given the same technique.** Before its numbers were locked, the baseline was turned to
  idle with `cpuidle-haltpoll` (forced on, Linux's own adaptive poll time), which took its
  cross-processor round trips from 165,000 to 400,000 a second on one pair.
- **One machine so far.** Every timing recorded here is from one Intel desktop processor (i9-12900K, performance
  cores) under KVM. aarch64 has run only under emulation, where timings mean nothing, and nothing has run on bare
  metal or on AMD. "Faster than Linux" is shown for that machine and no other. On a second x86 vendor, on
  real aarch64 and without a hypervisor Silica is held by its ratchets and Linux is not measured; a constant chosen
  by a sweep (the idle watch) is re-swept there or replaced by a boot-time measurement.
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
- **A gate must be able to fail.** Each gate has a test that plants a regression and sees the gate fail. The same
  holds for what is not run again: `tools/tests/evidence.sh` changes each kind of input and sees the check run, and
  `tools/tests/bench.sh` sees a kept result that misses its gate fail as a measured one does. A metric
  that is missing at its milestone fails. A check on something that does not exist yet reports SKIP, never pass. A
  result that exists and misses its gate (slower than Linux, over its budget, worse than its ratchet) fails at every
  milestone: the milestone column says when a metric must exist, never when it may lose.
- **Real hardware has the last word.** Every gate is measured again on the reference machines at M8.

### 4.2 Gates

The numeric limits below were set by judgment before anything could be measured. The first real measurement of
each either confirms it or replaces it, with the measurement recorded beside the new number, and from then on the
ratchet holds it.

A gate below that names Linux, for a metric with no number in `os/bench/reference.tsv`, is held by its ratchet;
Linux is not measured to supply one.

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
gate that let it through would defer the discovery to a rewrite. Every gate is also a ratchet. A gap that is not
closed at once is not waved through either: it is recorded with its bound (section 4.1, "A known gap is
recorded"), fails again the moment it grows, and blocks the milestone.

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
| Driver crash recovery: kill virtio-blk and virtio-net during sustained I/O | service resumes within 250 ms; zero committed writes lost, verified by the host; open connections continue | M3 |
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
