# Silica

Silica is a 64-bit Rust operating system with a capability microkernel, typed IPC and native userspace drivers. The current x86_64 UEFI loader boots in QEMU. The architecture and planned system interfaces live in the [spec repository](https://github.com/project-silica/spec).

## Build and boot

```sh
git clone https://github.com/project-silica/workshop.git
cd workshop
./bootstrap.sh
./tools/init.sh
./tools/boot.sh
```

Run `./tools/test.sh --fast` for host tests, target builds and the boot smoke test. Use `./tools/test.sh --full` for the broader test suite. Each component directory is a Git checkout. The build tools live in `os/tools`.
