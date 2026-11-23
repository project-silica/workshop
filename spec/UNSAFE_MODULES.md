# Modules allowed to contain unsafe code

Document each unsafe invariant at the call site.

| Repo | Path | Why `unsafe` is needed |
| --- | --- | --- |
| kernel | `kernel-core/src/mem.rs` | Turning a physical address from a capability into a reference to the kernel object stored there; zeroing and copying physical memory |
| kernel | `kernel/arch/` | Entry and exit stubs, context switch, boot trampoline, CPU feature probes, control registers, port and MMIO access |
| kernel | `kernel/src/main.rs` | Kernel entry symbol and panic handler |
| kernel | `boot-uefi/src/` | UEFI calls through firmware tables, loading the kernel image, jump to the kernel |
| kernel | `libsys/src/arch/`, `libsys/src/buffer.rs` | The syscall instruction, the timestamp counter and process entry; the IPC buffer's words, read and written at the address its constructor's caller vouched for. The rest of `libsys` contains no unsafe code; it declares as `unsafe fn` the operations that can remove memory or a stack from under running code |
| kernel | `roottest/src/` | The in-OS test program: deliberate faults, thread entry points, code it writes and then executes |
| kernel | `kernel-core/tests/support/`, `kernel-core/src/proofs.rs`, `kernel-core/src/exhaustive.rs` | The host test machine, the Kani harness and the exhaustive revocation check: memory from a `Vec` or an array presented to the kernel as physical memory |
| kernel | `kernel-core/tests/loom_models.rs` | The loom models of the kernel's locking: the state a lock protects is a loom `UnsafeCell`, read and written inside the lock the model is checking |

| system | `rt/src/` | Process entry and the panic handler; the IPC buffer's address; `mem` (revoking and freeing memory the program promises not to use; a program's own memory and lent memory as `Mmio`, safe because their addresses are never reused); `heap` (the allocator: free lists threaded through the free memory itself); `mmio` (volatile reads and writes of device registers, and copies in and out of device and shared memory, each byte once, bounds-checked); `ring` (the rings' header words as atomics over shared memory another program writes concurrently); `log` (the program's log ring, behind a flag); `random` (the generator's state behind a spin lock) and the start (the seed read from the start-up page and overwritten) |
| system | `proc/src/` | Filling a child's memory through the parent's scratch mapping; the root task's view of the ramdisk |
| system | `init/src/`, `systest/src/`, `stress/src/`, `devmgr/src/` | Program entry symbols; destroying objects the program made and no longer uses; `devmgr`: firmware tables and configuration space mapped from device memory |
| system | `drivers/framework/src/` | Mapping a device's registers and DMA memory as `Mmio`; everything else in a driver goes through those accessors |
| system | `rt/fuzz/fuzz_targets/`, `drivers/framework/fuzz/fuzz_targets/`, `drivers/nvme/fuzz/fuzz_targets/`, `devmgr/fuzz/fuzz_targets/` | The fuzz targets: host memory of the target's own presented as `Mmio`, standing in for the registers and shared memory a hostile device or peer writes |

A program's own shared memory and lent memory are reached through `silica_rt::mem::Memory::shared` and `silica_rt::mem::peer`, which need no `unsafe` in the program. `tools/test.sh` checks this table: an `unsafe` block or impl in any file outside these paths fails the `unsafe` check.
