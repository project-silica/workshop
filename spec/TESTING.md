# Testing Silica

Run `tools/test.sh --fast` for host tests, target builds and a QEMU boot. Run `--full` for host and guest coverage, Miri, loom and tool regressions, or `--deep` to include fuzzing. Run a single guest case with `--guest NAME`. Additional guest tests are listed in `kernel/tests/inos-<architecture>.txt`, one name per line. The result and failure details are available under `target/logs/`.

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

Baseline: a minimal Linux (current LTS, same QEMU/KVM configuration, same
vCPU and RAM), built once by `tools/bench.sh --build-baseline`.

Must win (gate fails otherwise, from the milestone listed):

| Metric | Target vs Linux | From |
| --- | --- | --- |
| Boot to first userspace process | faster | M2 |
| Boot to network-ready server | faster | M4 |
| Idle memory, server image | at most 25% of Linux baseline | M4 |
| IPC round trip (same core) | under 2x a Linux `pipe` ping-pong | M2 |
| Context switch | at or below Linux | M2 |
| Driver crash recovery: kill the virtio-blk and the virtio-net driver process during sustained I/O | service resumes within 1 s with no loss of committed writes. The Linux result for the equivalent fault (driver forcibly unbound under the same load) is recorded, not gated | M3 |
| p99 scheduling latency under load | at or below Linux | M3 |
| Cold start of a native app | faster | M6 |

Allowed to trail, tracked with a ceiling:

| Metric | Ceiling | From |
| --- | --- | --- |
| Small-file metadata throughput | within 1.5x | M5 |
| TCP throughput, single stream | within 1.25x | M4 |
| Block 4K random IOPS: virtio-blk from M5, NVMe added at M8 (when E05 lands) | within 1.25x, each against the same device on Linux | M5 |

A regression of more than 5% on any tracked metric fails the nightly. Size
budgets from ARCHITECTURE.md section 2 are checked by `tools/test.sh --fast`.
