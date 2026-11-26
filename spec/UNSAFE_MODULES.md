# Modules allowed to contain unsafe code

`tools/test.sh` reads this table: an `unsafe` block or impl in any file outside these paths fails the `unsafe`
check. State each use's invariant at the call site.

| Repo | Path | Why `unsafe` is needed |
| --- | --- | --- |
| kernel | `kernel-core/src/mem.rs` | A capability's physical address as a reference to the kernel object there; zeroing and copying physical memory |
| kernel | `kernel/arch/` | Entry and exit stubs, context switch, boot trampoline, CPU features, control registers, port and MMIO access |
| kernel | `kernel/src/main.rs` | Kernel entry symbol and panic handler |
| kernel | `boot-uefi/src/` | UEFI calls, loading the kernel image, the jump to it |
| kernel | `libsys/src/arch/`, `libsys/src/buffer.rs` | The syscall instruction, the timestamp counter, process entry; the IPC buffer's words |
| kernel | `roottest/src/` | The in-OS test program: deliberate faults, thread entries, code it writes and runs |
| kernel | `kernel-core/tests/support/`, `kernel-core/src/proofs.rs`, `kernel-core/src/exhaustive.rs` | Host memory presented to the kernel as physical memory in tests and proofs |
| kernel | `kernel-core/tests/loom_models.rs` | State a modelled lock protects, as a loom `UnsafeCell` |
| system | `rt/src/` | Process entry and panic handler; the IPC buffer; `mem` (freeing memory the program promises not to use; own and lent memory as `Mmio`, an address mapped again only once nothing refers to it; the program's blocks as a buddy tree; `SharedMemory` and `OwnedObject` free on drop); `heap` (free lists in free memory, per-unit records in the heap's window); `mmio`, `ring`, `log`, `random` |
| system | `proc/src/` | Filling a child's memory through the parent's scratch mapping; the root task's view of the ramdisk |
| system | `init/src/`, `systest/src/`, `stress/src/`, `devmgr/src/` | Program entry symbols; destroying objects the program made; `devmgr`: firmware tables and configuration space |
| system | `drivers/framework/src/` | Device registers and DMA memory as `Mmio`; drivers go through those accessors |
| system | `rt/fuzz/fuzz_targets/`, `drivers/framework/fuzz/fuzz_targets/`, `drivers/nvme/fuzz/fuzz_targets/`, `drivers/e1000e/fuzz/fuzz_targets/`, `devmgr/fuzz/fuzz_targets/` | Host memory standing in for registers and shared memory a hostile device or peer writes |

Programs reach their own and lent memory through `silica_rt::mem` (`Memory::shared`, `SharedMemory`, `Lent`,
`peer`) without `unsafe`.
