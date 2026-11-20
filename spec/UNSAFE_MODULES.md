# Modules allowed to contain unsafe code

Document each unsafe invariant at the call site.

| Repo | Path | Why `unsafe` is needed |
| --- | --- | --- |
| kernel | `kernel/arch/` | Entry and exit stubs, context switch, boot trampoline, CPU feature probes, control registers, port and MMIO access |
| kernel | `kernel/src/main.rs` | Kernel entry symbol and panic handler |
| kernel | `boot-uefi/src/` | UEFI calls through firmware tables, loading the kernel image, jump to the kernel |
| kernel | `libsys/src/arch/` | The syscall instruction and the vDSO entry (`libsys` is otherwise safe) |

Planned, to be added to the table when the code exists: the native runtime's process startup and TLS (`system/rt/`), the
userspace allocator (`system/rt/alloc`), the ring library's shared-memory accessors (`system/rings/`), and each
driver framework's MMIO and DMA accessors (`drivers/framework/`).
