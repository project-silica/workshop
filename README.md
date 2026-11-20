# Silica

Silica is a 64-bit Rust operating system with a capability microkernel, typed IPC and native userspace drivers. The current x86_64 UEFI loader boots in QEMU. The architecture, milestones and planned system interfaces live in [`spec/`](spec/README.md).

## Build and boot

```sh
git clone https://github.com/project-silica/workshop.git
cd workshop
./bootstrap.sh
./tools/init.sh
./tools/boot.sh
```

Run `./tools/test.sh --fast` for host tests, target builds and the boot smoke test. Use `./tools/test.sh --full` for the broader test suite. `spec/` is part of this repository; `idl`, `kernel` and `os` are separate Git checkouts pinned in `bootstrap.pins`. The build tools live in `os/tools`.
