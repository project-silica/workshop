# Silica

Silica is an operating system built on a small capability microkernel written in Rust: typed calls between programs, drivers and services outside the kernel, no `fork`, signals, TTYs, uid 0 or global namespace. Today the kernel runs on x86_64 and aarch64 with multiple processors under QEMU, starts programs in their own address spaces, and carries protocol calls and capabilities between them; `./tools/boot.sh --arch aarch64` boots the Arm build. The design, the milestones and what finished means are in [`spec/`](spec/README.md).

## Build and boot

```sh
git clone https://github.com/project-silica/workshop.git
cd workshop
./bootstrap.sh
./tools/init.sh
./tools/boot.sh --system
```

`./tools/test.sh --fast` checks the integrated build in under a minute; `--full` adds the complete guest tests, Miri, loom and the tool self-tests; `--deep` adds fuzzing and the benchmarks against a Linux baseline built from pinned source (`./tools/bench.sh`).

`spec/` is part of this repository. `idl` (the protocol language and its compiler), `kernel`, `system` (the runtime and the first programs) and `os` (image builder and tools) are separate Git checkouts pinned in `bootstrap.pins`. `tools` links to `os/tools`.
