# Modules allowed to contain unsafe code

Document each unsafe invariant at the call site.

| Repo | Path | Why `unsafe` is needed |
| --- | --- | --- |
| kernel | `kernel-core/src/mem.rs` | Turning a physical address from a capability into a reference to the kernel object stored there; zeroing and copying physical memory |
| kernel | `kernel/arch/` | Entry and exit stubs, context switch, boot trampoline, CPU feature probes, control registers, port and MMIO access |
| kernel | `kernel/src/main.rs` | Kernel entry symbol and panic handler |
| kernel | `boot-uefi/src/` | UEFI calls through firmware tables, loading the kernel image, jump to the kernel |
| kernel | `libsys/src/arch/` | The syscall instruction, the timestamp counter and process entry. The rest of `libsys` contains no unsafe code; it declares as `unsafe fn` the operations that can remove memory or a stack from under running code |
| kernel | `roottest/src/` | The in-OS test program: deliberate faults, thread entry points, code it writes and then executes |
| kernel | `kernel-core/tests/support/` | The host test machine: memory from a `Vec` presented to the kernel as physical memory |

Planned, to be added to the table when the code exists: the native runtime's process startup and TLS (`system/rt/`), the
userspace allocator (`system/rt/alloc`), the ring library's shared-memory accessors (`system/rings/`), and each
driver framework's MMIO and DMA accessors (`drivers/framework/`).
