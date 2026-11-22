# Silica architecture

Design decisions, rationale and compatibility boundaries.
The escape hatch is what keeps a wrong decision from forcing a rewrite.
This is the current best design, open to challenge on evidence (see `AGENTS.md`). Change it as part of the
same piece of work as the code that shows a decision was wrong, and say what convinced you.

## 1. Shape

Capability-based microkernel. Everything else runs in isolated userspace
processes that talk over typed IPC. This is the seL4 / Zircon lineage. It is
the only proven design that gives small size, fault isolation, and a security
model stronger than Linux at the same time.

Where seL4 and Zircon differ, follow seL4: fewer object types, fewer syscalls,
no kernel heap, no policy in the kernel. Take from Zircon only what costs no
kernel code (the vDSO-only ABI, userspace pagers, the IDL-first service model).

Hard rules:

- 64-bit only, everywhere. No 32-bit kernel, no 32-bit userspace, no compat mode, no 32-bit syscall entry, no x32. The kernel never leaves long mode.
- No 30-year-old hardware interfaces and no Unix conventions (section 3). Hardware that is merely older but still common in working machines (SATA, I/O ports, line interrupts) is supported.
- No compatibility layers, shims, or emulation of other operating systems, in the kernel or above it (section 11).

- Reason: a monolithic kernel cannot be small, cannot restart a crashed driver, and puts every driver bug in ring 0.
- Escape hatch: the kernel's syscall surface is private (section 4). Any server can be merged into another address space later for speed without changing any application.

## 2. Size budgets (enforced by `tools/size.sh`)

| Artifact | Budget | Required from | Rationale |
| --- | --- | --- | --- |
| IPC fast path + context switch + syscall entry | 32 KB text | M2 | fits L1i |
| Kernel image, text + rodata | 256 KB | M1 | fits L2 on any CPU since 2015 |
| Kernel + core servers (init, memory, process, vfs, net, block) resident text | 2 MB | M5 | fits L2 on current desktop/server CPUs, L3 everywhere |
| Minimal server image (boots, serves TCP, SSH-equivalent) | 16 MB on disk | M4 | |
| Desktop image without browser | 128 MB on disk | M6 | |

From its milestone on, an artifact that is missing fails `tools/size.sh`; before
that it is skipped. The bloat ceilings below are required from M1. The images
measured are the files the milestone exit test boots, not a separate build.

Bloat ceilings, also enforced by `tools/size.sh`:

| Measure | Ceiling |
| --- | --- |
| Kernel source, excluding tests and the three arch directories | 12,000 lines of Rust |
| Each arch directory | 4,000 lines |
| Syscalls (every kernel operation is its own syscall; there is no multiplexed invoke) | 32 |
| Kernel object types | 10 |
| Heap allocations inside the kernel after boot | 0 |

A change that breaks a budget is not finished, even if its tests pass. Raise a
budget only with the measurement that justifies it written beside the new number.

## 3. What is deleted (the legacy list)

| Legacy abstraction | Replacement |
| --- | --- |
| `fork`/`exec` | `spawn(image, capabilities)`; child gets only what the parent hands over |
| Ambient authority, uid/gid, root | Capabilities only. No user identity in the kernel. Users are a policy service. |
| Global filesystem namespace | Per-process namespace built from directory capabilities |
| Signals | Typed async messages on a channel; exceptions delivered to a supervisor port |
| `ioctl` | Typed IPC protocols defined in IDL |
| "Everything is a file" | Everything is a typed object behind a capability |
| Blocking syscalls for I/O | Shared-memory submission/completion rings; sync call is a library wrapper |
| TTY/PTY line discipline | Terminal is a userspace protocol over a channel |
| BIOS, CSM, MBR, PIC, PIT, xAPIC, PS/2, VGA text, IDE, floppy, parallel, ISA | UEFI, GPT, x2APIC, the TSC-deadline timer on an invariant TSC, USB HID, GOP framebuffer, NVMe/AHCI/virtio. An x86_64 machine without x2APIC, TSC-deadline, XSAVE and AVX2 (anything before 2013) is not supported, and the kernel says so at boot |
| 32-bit, compat mode, segmentation, real mode | 64-bit only; the kernel never leaves long mode |
| Kernel heap, kernel-side allocation policy | Untyped memory: userspace supplies the memory for every kernel object (section 6) |
| Kernel modules | Userspace driver processes, restartable |
| Text config scattered in `/etc` | One typed, versioned, transactional config store |
| In-place package installs | Content-addressed immutable packages, A/B atomic system updates |
| Setuid, sudo | Capability delegation through a broker service with user consent |

Old things kept because firmware or the internet require them, all outside the
kernel: FAT32 for the UEFI system partition, ACPI (AML interpreter in a
userspace service), IPv4 alongside IPv6.

## 4. Stable ABI (the anti-lock-in decision)

Syscall numbers and layouts are **not** stable and are never called by
applications. The stable contract is:

1. The IDL protocol definitions in `idl/` (versioned, additive evolution only).
2. `libsys`, a small shared object the kernel maps into every process (vDSO style). Applications link against it.

The compatibility promise starts with the first `stable` release (`spec/CI_RELEASE.md` section 8; not before the M9 exit test passes). Until then every protocol is provisional: when use shows a protocol is wrong, replace it through a staged migration (add the new one, move the provider and every consumer, then remove the old one). Each single change is still additive or a removal of something unused, so no commit breaks a build. From the first `stable` release on, nothing published is removed or changed. That release waits for the outside-developer trial (`spec/CI_RELEASE.md` section 9), so its findings can still change the design.

- Reason: Linux cannot fix its syscall mistakes because binaries call them directly. This design lets the kernel be rewritten under running software.
- Escape hatch: this is the escape hatch for nearly everything else.

## 5. Kernel contents (and nothing else)

Address spaces and page tables. Threads. Scheduling. Capabilities and
capability spaces. IPC (synchronous call/reply, async notifications, shared
memory objects). Interrupt routing to userspace. Timers. IOMMU programming.
Exception delivery. Boot handoff.

Not in the kernel: filesystems, network stack, drivers (except the interrupt
controller, timer, and early serial), process policy, naming, security policy.

## 6. Kernel mechanisms

- **Objects (10, final)**: Untyped, CapSpace, Thread, AddressSpace, Frame (memory, any power-of-two size from a page up), Endpoint (synchronous IPC), Notification (async signal, also carries interrupts), SchedContext (CPU budget), Hw (a hardware resource that is not memory: a range of I/O ports, interrupt lines or device identities, the kernel's console, or the power switch; created at boot and only ever narrowed), Vcpu (M9). There is no Channel, Port, Timer, Interrupt, PageTable or Job object: each is either expressed with these ten or lives in userspace.
- **Untyped memory**: all physical memory is handed to the root task as Untyped capabilities at boot. Every kernel object is created by retyping Untyped memory that the caller owns. The kernel has no heap and never allocates after boot. Resource accounting, quotas and "jobs" are therefore userspace policy with no kernel code. Revoking an Untyped destroys everything made from it. Memory whose contents must be kept (device registers, firmware tables, the ramdisk) comes as Untyped that is never zeroed and becomes only frames and smaller Untyped; whether a frame maps with device attributes is a separate property, so the ramdisk maps as ordinary memory.
- **Capabilities**: unforgeable handles with a rights mask, named by slot index in the caller's CapSpace (one flat table per CapSpace, no guards or multi-level addressing; an operation on another CapSpace names that CapSpace's capability and an index). Every capability has a place in a derivation tree. *Derive* makes a child with equal or fewer rights that depends on its source; *duplicate* makes an independent sibling; *move* keeps the place. A capability never outlives what it was derived from: deleting one deletes its descendants, so no descendant is ever re-parented and every step of delete and revoke is O(1) and preemptible. Lend with derive, hand on with duplicate or move. An Untyped has exactly one capability (split it by retyping). No capability, no access. No exceptions.
- **Kernel execution**: one kernel stack per processor with a guard page, interrupts off in the kernel, no blocking inside it. Every entry runs to completion and returns to the thread the scheduler picks. Long operations (zeroing a large Retype, revoking a large tree) poll for a pending interrupt, record their progress in the objects, and restart. The kernel never dereferences a user virtual address: message words beyond the registers travel through the thread's IPC buffer Frame, reached through the kernel's map of physical memory. A system call preserves what a function call preserves (callee-saved general registers and the floating-point control words) and, like a function call, not the vector registers; so a thread switched out inside a system call needs no extended-state save, and when it resumes its vector registers are cleared. Interrupted and faulted threads get a full save and restore. The scheduler runs on the way out only when an entry changed something it cares about.
- **IPC**: synchronous call/reply on Endpoints with direct thread switch (a call runs the waiting receiver at once, its reply runs the caller at once, both inside the caller's time slice) and register passing. A message carries up to 500 words (four in registers, the rest through the IPC buffers) and up to four capabilities, each lent (derived: the sender can revoke it), duplicated or given (moved); sending capabilities needs the GRANT right, a reply may always carry them. A server that must answer out of order receives with a notification to park the call on and answers by sending to that notification: a notification is a place a thread waits, so no reply object type is needed. An operation is tied to the capability it was made through: when that capability leaves its slot (deleted, revoked through an ancestor, or moved away) while the operation still waits (a queued send or call, a receive, a call delivered and not yet answered, parked or not), it fails with `Gone`, and a server replying to such a call finds no caller (`NoCaller`); operations through other capabilities to the same endpoint are untouched, and the slot can be granted again at once. Destroying an endpoint is the same for all of its capabilities together. So revoking a client's capability stops that client now, including the reply it was waiting for. A receive on an endpoint can name a notification to listen on as well: a signal pending there, or arriving while the thread waits, ends the receive with the notification's word and a descriptor (`MsgInfo::NOTIFIED`) the kernel clears from every message, so none can imitate it. That is the loop of every driver and server (callers, interrupts and clients' wake-ups heard by one thread in one wait, `silica_rt::ipc::serve_events`), with no second thread, no poll, and the steady state (reply, then receive and listen again) on the fast path. A server with long-poll methods (the console's `read_line`, which waits for a line to be typed) has every call parked as it arrives (`serve_parked`) and answers each when its event comes, at one system call more per call. One thread listens on a notification at a time; taking the notification away ends the receive with `Gone`. (seL4 binds a notification to a thread for the same purpose; naming it in the receive keeps the binding out of the thread object and lets a thread listen on different notifications in turn.) Streams, channels, ports and shared submission/completion rings are userspace libraries built from Frames plus Notifications (`silica_ring`: one producer, one consumer, a system call only when the other side said it sleeps). The kernel knows nothing about them.
- **Firmware's memory**: what the firmware keeps in RAM (ACPI tables, runtime services) is handed over as kept memory that maps as ordinary memory (`KIND_FIRMWARE`), apart from memory-mapped I/O and reserved ranges, which are device memory. Tables are read with ordinary loads; a device mapping faults on an unaligned load on Arm, which is how the difference was found.
- **Memory**: userspace pagers handle faults (a fault is a call to the thread's fault endpoint; the reply resumes it, and can carry the frame to map so the usual cure costs one kernel entry). An AddressSpace object carries the memory for its own page tables and `Map` fails with `NoMemory` when that runs out, so table memory is paid for by the owner like everything else. A failed Map preserves every translation and the remaining table capacity. One Frame capability maps at one place; copy it to map it twice. Deleting a Frame capability, or the address space, removes the mapping. No mapping is writable and executable at once. Page-table entries are written with their accessed and dirty bits already set (x86): the kernel keeps no page ages, and letting the processor set them cost more than the rest of a fault; a pager that wants to know which pages were used will ask for it explicitly (not built: nothing needs it before swap, D04). Frames of 2 MiB and up use large pages. No overcommit, no OOM killer; allocation fails at the caller.
- **Scheduler**: per-CPU run queues; a fair class plus a deadline class with admission control; scheduling-context capabilities so budget is delegated across IPC (priority-inheritance by construction); core-type aware (P/E cores, not yet); tickless. A SchedContext is the authority to a share of processor time: fair (a weight; an unbound thread has the default weight) or deadline (a budget per period on one processor, admitted only while the processor's reservations stay at or below 90%, run earliest deadline first ahead of all fair work, and held back once spent until the next period: a hard reservation). Several threads may share one. Fair threads are ordered by virtual runtime (real time scaled by default weight over weight); the running one is preempted once it is 3 ms ahead of the next; a thread that slept is placed at most 3 ms behind the least-run one and takes the processor at once when it is 1 ms or more behind the running one, while a thread that has never run starts level with the least-run one. Time is charged to the processor's account, the thread last picked from a queue: a direct IPC hand-off does not change it, so a server running on a call spends its caller's share or budget, and the IPC fast path reads no clock. The timer is set exactly for the next preemption, budget exhaustion or refill. Cost, the kernel benchmarked before and after in one session on the reference host: a context switch by yield 212 to 218 ns at the processor's base frequency (138 to 142 ns with turbo; 314.6 to 379.7 instructions: the clock read, the charge and the next slice deadline that fairness needs on every switch), an IPC round trip 412 to 413 ns (977.6 to 994.7 instructions). Known limit: the fair queue is a list kept in order, so a wake-up costs a walk over the threads queued on that processor; a tree replaces it when a measurement with many runnable threads per processor shows the walk. Measured in the guest: weights 1024 and 3072 share a processor 1:3.00; a 2 ms in 10 ms reservation beside three fair spinners gets 19.8%; a thread that mostly sleeps wakes within microseconds beside two spinners.
- **SMP**: every thread has a home processor and runs only there (moving it is an explicit operation; balancing is userspace policy). A move is invisible to the thread moved, so a balancer needs no cooperation from what it balances: a runnable thread runs on its new processor next, one waiting for a reply is answered there, one blocked in a send or receive makes the same call again there (a `ReplyRecv` that has replied only receives), and a system call overtaken while it waited for a processor's lock is made again (each architecture's entry marks, before it says it is in the kernel, whether a system call saved the frame). Measured: a client and server moved 87,000 times between eight processors during 200,000 round trips lose and repeat nothing (systest, aarch64). Kernel state is protected by one lock per processor, used at four levels. *Local*: a kernel entry holds its own processor's lock and may change that processor's scheduling state, its threads, and the endpoints and notifications it owns (those whose last waiting receiver is one of its threads); a call and its reply between threads of one processor never write memory another processor uses, so independent workloads scale with the processors. *Pair*: a message between threads of two processors, or through a queue the other one owns, adds the other processor's lock (both taken in index order) and checks again that everything it touches belongs to one of the two, so a client and server on different processors do not stop the rest of the machine; a waiter whose deadline passes while it sits in a queue another processor owns is taken out globally. *Structure*: mapping a frame keeps the local lock and adds one lock shared by all mapping, so a fault resolved by a pager stops nobody. *Global*: an operation that changes capability slots, removes mappings, or touches another processor's threads or queues lets go of its own lock and takes every processor's in index order; holding them all it is the only code in the kernel, and before it lets memory be reused it interrupts every processor that might still run on that memory in user mode and waits until it has entered the kernel (so TLB shootdown, thread destruction and address-space destruction are synchronous). A processor that waited for its lock re-examines its current thread: it may have been stopped or destroyed. Each processor's lock and state have their own cache lines. The lock protocol is modelled under `loom`. Known limit, to be measured before it is changed: global operations cost one lock per processor. A system call takes its processor's lock with one atomic exchange before it saves the register frame (when the lock is free nobody can look at the frame, and fewer stores wait to drain); that exchange, about 3 ns of a 55 ns null system call on the reference host, is what this design costs on the local path over a uniprocessor kernel, and it is why `null_syscall` is 2 ns behind its uniprocessor ratchet. Removing it would mean no processor ever takes another's lock (requests posted to the other processor instead), which puts an interprocessor interrupt on every cross-processor call; that trade is decided by measurement on real hardware (M8), not here. Calls, replies and fault deliveries between threads of one processor through endpoints it owns, without capabilities, take a fast path that checks every condition first and otherwise falls back to the general path unchanged.
- **Logs**: a service prints into a ring of its own (`silica_rt::log`, 16 KiB of 56-byte records in a frame the service manager makes for it before anything starts), never waiting: text that does not fit is lost and the loss is said in the log when there is room. The log service (`logd`, `silica.log.Reader`) is given every ring and the notification their writers signal at its start, keeps the last 32 KiB of each service's text, and puts the text on the console as it comes (an unfinished line too: a prompt), starting another service's text on a fresh line. The service manager never calls it: before it reports a check's result or turns the machine off it signals a flush bit and waits at most 200 ms for the answer, so a log that hangs costs the system its log, not its manager. The shell's `log <service>` reads it. Programs without a ring (the root task, drivers, which the device manager starts) still print to the kernel's console. Owed: drivers' logs, levels and structure (a record per event, not text), persistence across a reboot.
- **Console and power**: the kernel owns one console (the serial port it logs and panics to); a holder of the console capability writes up to 32 bytes per call to it, so bring-up and panic output needs no driver in any program, and the kernel writes each of its lines whole, and a program's text of up to 224 bytes too (pieces marked as having more to follow are held in the thread object, 192 bytes, and written with the last), so lines never tear; a writer that finds the line left unfinished by another (a shell's prompt) starts a fresh one, so a line a reader anchors on never begins with someone else's text. `silica_rt`'s `println!` formats a whole line before writing it. (With 32-byte pieces only, two programs' lines interleaved at 32 bytes on two processors, which hid a passing test's line from its harness.) The power capability turns the machine off or resets it: PSCI SYSTEM_OFF and SYSTEM_RESET on Arm; on x86 ACPI S5 (the FADT's PM1 control registers, the DSDT's `\_S5` values read by `formats::acpi` without an AML interpreter, the machine put in ACPI mode first if the firmware left it out) and the FADT's reset register. The kernel stops nothing first: logging (D08) and the shutdown service (D16), which stops services in order and flushes storage, are built on these, not beside them. Known hazard: the x86 kernel also writes the QEMU debug-exit port (0xF4) whenever it stops, which on real hardware is an unknown port; it is to be written only when the command line names a harness, as on Arm (C35).
- **Time**: monotonic clock from the invariant TSC (or arch equivalent), calibrated from CPUID, the hypervisor's clock, or the ACPI PM timer; read in userspace without a syscall. An idle processor arms its timer ahead of the next deadline by its measured wake-up latency (a running average, capped at 50 us) and spins the rest, so deadlines are met to within a microsecond instead of late by the time a virtual processor takes to be woken. A processor with nothing to run first watches its presence word for 5 us before it halts: whoever has work for it meanwhile says so with one compare-and-swap instead of an interrupt (if the watcher has already swapped itself to halted, that fails and the interrupt is sent: one of the two always succeeds, modelled under `loom`). The processor says "watching" while it still holds its lock, and reaches "halted" only by that swap: the watch lets interrupts in on every turn and does not end for one, so an interrupt sent to a processor that is about to watch would be taken and the halt after it never ended (the first version said "idle" under the lock and "watching" after it; under KVM the gap is a few instructions and nothing showed, under emulation the aarch64 cross-processor tests hung), and a deadline inside the watch needs no timer. Swept (`bench.sh --sweep IDLE_WATCH`): cross-processor round trips on one pair 218,000 a second with no watch, 1,041,000 with 5 us, no more with 20 or 200 us, nothing else changed; against Linux with its own idle polling on, 2.5 times its 400,000. The watch is power spent on a guess, so it is about what the halt and wake it avoids cost; a longer or adaptive one waits for a workload whose partner is slower than a ping. Known limit: 5 us was swept on one machine (i9-12900K, under KVM); the length should come from the halt-and-wake cost the processor measures on the machine it boots on, as the timer's wake-up latency already does, and that is owed before drivers are tuned against it (M3). There is no timer object: a receive takes an absolute deadline, so a sleep is a wait on a notification nobody signals and a timeout is the same call. Wall clock is a userspace service.
- **Interrupts**: every device interrupt is bound to a Notification by the holder of an interrupt-line capability and arrives as that capability's badge, on the binder's processor. A level-triggered line is held off after each interrupt until its driver acknowledges it, so a stuck device costs its driver, not a processor. Lines the I/O APICs wire are numbered as ACPI numbers them; the lines above them (`RootInfo::msi_first`) are message-signalled: `IrqBind` with `IRQ_MSI` binds one for a single device (named through a device-identity capability) and returns the message the driver writes into that device's MSI-X table. On Arm the message lines are LPIs through the GICv3 ITS (`its.rs`: the LPI property and pending tables, the ITS's device and collection tables and command queue, carved at boot; a line is an event of its device's translation table, the device named by its PCI requester ID). Found on the way: the interrupt loop took every identifier from 1020 up for "nothing pending" and returned without ending it; LPIs start at 8192, so the first one left the CPU interface's running priority raised and every later interrupt, the timer's too, was never signalled. Known limits: one vector space for the machine (192 lines in all, where Linux has about 200 per processor; per-processor vector tables when a machine needs more), and no interrupt remapping yet, so nothing checks which device sent a message and a device that can do DMA can forge another line's by writing to the interrupt address range. A forged interrupt is a spurious notification to a driver, which drivers must tolerate anyway, never a breach of memory; remapping is owed before M3 exits (C32).
- **Devices and DMA**: an AddressSpace can be made *for devices* (`ASPACE_IO` at Retype). It is the same object with tables in the IOMMU's format: the frames mapped in it are what the devices attached to it reach by DMA, at the addresses they are mapped at, readable or writable as mapped. `DeviceAttach` attaches a PCI function (segment, bus, device, function) to one, through a device-identity capability covering it, or detaches it. A device reaches nothing before it is attached, exactly what is mapped while it is, and nothing once the address space is destroyed; so ending a driver, however it ends, cuts its device off from memory in the same revocation that takes the driver's memory back, and the frames can be reused at once. `Unmap` (and deleting or revoking a mapped frame capability) returns after the IOMMU has dropped the translation. A lender's revocation therefore takes a frame away from a device as surely as from a program. Device addresses are chosen by the driver (by convention its own virtual addresses), so a driver never learns a physical address. The kernel carves the IOMMU's own tables at boot: a root table, context tables for 64 buses with attached devices (`NoMemory` beyond; a server with devices on more buses needs the pool sized from the firmware's bus count), a queue page per unit. Intel VT-d on x86_64 (legacy second-level tables, queued invalidation waited for, 39 or 48 bits, 2 MiB pages where the unit has them; every unit shares one root table, so the kernel need not know which unit a device is behind; units of other PCI segments get an empty root and their devices reach nothing). A refused access is logged with the device, the address and the direction. Cost, measured: switching translation on is 1.1 ms in QEMU's emulated VT-d (the emulator rebuilds every device's view of memory; setting the root table and the first invalidation take 0.24 ms more), so the held host's boot went from 16.77 ms (the kernel before this, on the same machine with the IOMMU present) to 18.7 ms, interleaved in one session (`bench.sh --compare`); before the machine had an IOMMU at all the boot was 13.77 ms. On hardware the same steps are register writes the unit completes in microseconds; the boot gate is measured again there (M8). The code that maps for devices is a copy of its own, dispatched before anything else in `Map`; even so the page fault's instruction count moved from 2766.3 to 2793.3 and the IPC round trip's from 994.7 to 1003.8 (a new test on `ReplyRecv`), and with the old mapping body verbatim the fault was still 2794: the compiler's register allocation around the inlined walk, shown instruction by instruction, not work the path does. Time, interleaved: page fault 569 to 571 ns, round trip 413 to 415 ns, context switch 217 to 218 ns, all within a nanosecond or two. Not yet: AMD-Vi, Arm SMMUv3, the firmware's requested mappings (RMRR: a device the firmware was still using, such as a USB controller in legacy emulation, reaches nothing once the kernel starts), and telling the owner about refused accesses other than on the console.
- **Machines without an IOMMU** (most virtual machines, `iommu=off` on the command line): there are no device address spaces, `DeviceAttach` is `Unsupported`, and a device that does DMA reaches all of memory whatever its driver holds. The kernel says so at boot and `RootInfo::dma_top` is 0. Only there, the holder of a device-identity capability may ask a frame's physical address (`Inspect`), which is the address the device needs; with an IOMMU nobody is told one. Starting a DMA-capable driver on such a machine is trusting it with the machine; that is the device manager's decision and it says so. The driver framework hides the difference, so a driver is written once.
- **Inspection**: `Inspect` reads kernel state through a capability and changes nothing: what a CapSpace slot holds and what a thread is doing. The owner's tools list every thread and capability from the capabilities the owner holds; there is no kernel debugger with its own authority.
- **HAL**: `kernel/arch/{x86_64,aarch64,riscv64}` behind one trait. x86_64 is built first; aarch64 must compile and boot by M2 so the trait stays honest.

Escape hatch: object set and rights are versioned in `libsys`; adding an object type is additive.

**Programs.** The kernel has no notion of a process. A program is what its parent makes with `silica-proc`: one
Untyped set aside for it, from which come its CapSpace, its address space, its first thread, its image, stack and
start-up record, and (half of it) its own Untyped to allocate from. It starts holding the few capabilities every
program has (itself, its memory, an endpoint to its parent) and the ones its parent listed, in the order listed;
nothing is inherited and there is nothing ambient to find. It ends by telling its parent, and the parent takes
everything back by revoking the one Untyped. Accounting, quotas and kill are therefore that Untyped
(`silica_rt` documents the convention; the kernel enforces only the capabilities).

**Calls between programs.** One IDL message is one kernel message: its bytes as message words, its capabilities
moved with it. A generated client talks through `silica_rt::ipc::Channel` (an endpoint capability); a provider
runs `silica_rt::ipc::serve` around the generated `dispatch`. The provider learns who is calling from the badge of
the capability the caller was given, which the caller cannot change.

## 7. Drivers

Userspace processes. Each gets: MMIO Frame caps (and Hw caps for the I/O ports and interrupt lines the device needs), Notifications bound to its interrupts, an
IOMMU domain, and nothing else. A driver host supervises and restarts them.
Driver interfaces are IDL protocols per class (block, net, display, input,
audio, usb-host, gpu).

How a driver meets its device (the seam, `silica_driver`'s documentation is the contract): the device manager finds
the machine's PCI functions (ACPI MCFG, configuration space), and starts a driver for each one it has a driver for
as an ordinary program whose grants are, in order: the endpoint its clients call it on, its device's identity, its
interrupt lines, its configuration space read-only, and one frame per memory BAR. Its arguments say which device,
which lines, how far device addresses go, and how many times it has been started. The driver makes its own device
address space from its own memory and attaches its device; until then the device reaches nothing. Configuration
space belongs to the device manager, which switches on memory decoding, bus mastering and MSI-X before the driver
runs and off when it ends: a driver cannot move its registers onto another device's. A driver that faults (its
faults go to the device manager's endpoint) or exits with a failure is destroyed, its device silenced, and it is
started again, at most three times, after which the device is left alone and the owner told (an owner's `restart`, through `silica.device.Manager`, is not counted). A client hears of its driver's end at once: `open` takes a notification the device manager signals when that driver ends, so a client sleeping on its device is not left waiting for a call to fail. `silica_block::client::Disk` uses it to survive its driver: it drains what the old driver completed, opens the new one, registers its memory again and sends again every request still in flight; to its program a driver's end is a delay of about a millisecond (blkload: nine kills under sustained writes, worst recovery 1.08 ms, every block verified on the host afterwards). The owner can put
another program in a driver's place (`driver=<vendor>:<device>=<program>`), which is also how the test of what a
driver cannot do runs: a hostile driver holding exactly what a real one holds.

Display and input (the local console's two devices, `silica.display.Device` and `silica.input.Device`) follow the block class's rule that a client's data stays in the client's memory. A keyboard driver writes key records (USB HID usages, down or up) into a ring in a frame the client lends and signals it when it sleeps; layouts are the client's. A display driver shows pixels from a frame the client lends (`attach`) and is told which rectangle changed (`present`, with the rectangle's offset and stride in that frame); a framebuffer driver copies the rectangle into the scanout memory, and a driver whose hardware scans out of system memory (virtio-gpu's resources, a GPU's) need not copy at all. So no client ever maps memory of a driver's: a driver that ends takes nothing the client is using, and the client reattaches to its successor (the device manager's death notice) and presents everything again. The local console does exactly that for both, and its test restarts each driver under a running shell. An earlier version lent the framebuffer itself to the client, which then faulted on its next write when the driver ended: the shape was wrong, not the driver. Memory a peer lent and took back is answered with zeros by every supervisor, not only the device manager (`silica_proc::Child::answer_peer_fault`, used by the service manager too), as `silica_rt::mem` promises every program.

The second block driver, NVMe (`system/drivers/nvme`, some 650 lines), was written by an agent from the published documentation alone (the rustdoc of `silica_rt`, `silica_driver` and `silica_block`, the protocol pages and this section) and passed the block tests at its first complete build. What it reported missing or ambiguous changed the interfaces, not the driver: a block driver can refuse a request it cannot express (`Refusal::Fail`; it had been signalling itself to fail one later), has a timer (`Device::deadline` and `timeout`, carried by `serve_events`' deadline; NVMe gives an I/O command 30 s, as Linux does, then ends and is restarted, which resets the controller), and has DMA barriers that are right on Arm (`dma::write_barrier`, `read_barrier`, `full_barrier`: `dmb oshst`, `oshld`, `osh`; the virtio queue read the used entry after the used index with no barrier at all). The documentation now states what the service checks before `start`, that `address` includes the offset, that DMA memory is contiguous and naturally aligned, how interrupts are numbered and that the MSI-X table is the framework's, what a 64-bit BAR looks like, how a driver ends, and a driver's `Cargo.toml`. The trial also found blkcheck never sent a request of more than one page, so a wrong scatter list passed; it now writes and reads up to 128 KiB starting part-way into a page (and a deliberately wrong PRP list fails it). Not yet: NVMe's single-vector fallback, 4 KiB-block namespaces, several namespaces or queues, the shutdown notification (drivers are not told of shutdown; data a client flushed is safe regardless).

A device is assumed to misbehave in every way its interface allows, and the test of that commits the faults on purpose: `inject=<driver>:<fault>@<n>` on the kernel command line has the first run of a driver commit one at its `n`th request, at the boundary where the device would (`silica_driver::inject`; the virtio queue and the NVMe driver commit all five): a completion of a request never offered, a request the device never sees, an interrupt with nothing done, a completion without an interrupt, a device that resets itself. A block driver gives each request a timeout (30 s, Linux's; 1 s in a run with a fault armed) through the service's deadline; when it passes the driver looks once more for completions whose interrupt was lost, and otherwise ends, as it does on nonsense from the device. A driver that ends leaves what was in flight to the client, which sends it again to the driver started in its place: completing it as aborted would have turned a driver's restart into a failed request. The `faults` test runs blkcheck through each fault on each block driver: every check passes, the three faults that cannot be absorbed cost one restart, the two that can cost none, and nothing outside the driver reports an error.

The network interface class (`silica.net.Device`, `silica_net`) is the block class's shape on the same data path: a transmit names a frame in the client's memory and completes when it is sent; a receive offers a buffer ahead of time and completes with the length of the frame that arrived in it; a record with the tag `LINK` says the link went up or down. The virtio-net driver (one queue pair, no offloads yet) puts a 12-byte header of its own in front of each frame and nothing else of its own on the path: the device reads and writes the client's memory through the IOMMU. `netcheck` tests it against QEMU's user-mode network with frames built by hand (ARP for the gateway, 200 pings), before any network stack exists. Its benchmark (`tools/bench.sh`) runs both systems against one host program on a tap interface with vhost-net (`os/bench/net/echo.c`, spinning on a held processor of its own, sending back one EtherType and dropping another), with the network device doing its DMA through the platform's translation on both machines, as real PCI devices do (Linux's AF_XDP zero-copy needs it). First measurement, same host, two boots each: round trip 6.4 to 6.6 us median and 7.2 to 8.6 us p99, against Linux's 7.4 and 10.0 to 10.3 us (AF_PACKET, blocking); 3.65 to 3.77 million 1514-byte frames a second sent, against Linux's 2.89 million through AF_XDP zero-copy (1.82 million through AF_PACKET). Its recovery is tested as the disk's is (`netload`, `run_net_recovery`): eight pings in flight to the user-mode gateway while the device manager restarts virtio-net every 200 ms for 3 s; no transmit fails, the slowest of 14 recoveries took 2 ms, and no ping had to be sent again (QEMU holds frames for a device with no receive buffers; on hardware the frames that arrive while no driver runs are lost, and are the network's to lose). The hostile driver runs in its place too (`rogue_net`): the network device's receives into memory never mapped for it, or mapped for reading only, and its transmits from unmapped memory are refused by the IOMMU and logged, as the disk's are; the injected faults run under `netfault` (netload's source, restarting nothing): garbage, a frame never sent and a device reset end the driver once, a spurious or missed interrupt is absorbed, and every ping after the recovery is answered. Owed: the receive rate under a flood, checksum and segmentation offloads, several queue pairs, and a missed receive interrupt on a quiet interface (it waits for the next interrupt; the timeout covers only frames being sent).

Devices come and go while the system runs (native PCI Express hot-plug, `devmgr`'s `hotplug`): the device manager arms every hot-plug capable port (its slot interrupts through the port's own MSI-X entry, on the device manager's one notification beside the power button), switches a slot's power on when a device arrives and waits for its link, gives the device's BARs addresses out of the windows the firmware left the port (a BAR at a multiple of its size; one that does not fit is reported with the windows as they are), and starts its driver; a request to take a device out (the attention button, which QEMU's `device_del` presses) ends its drivers and switches the slot off, after which it can be pulled. The `hotplug` test puts a disk in at runtime, runs blkcheck on it from the shell, and takes it out. Not yet: bridges and switches behind a slot (only the devices on the port's own bus), surprise removal without the button, and ACPI hot-plug (QEMU's default on q35, off in the test machine).

Every driver is written natively in Rust against the class protocols. There
is no wrapper, shim, or compatibility host for drivers from another operating
system, now or later.

Order: virtio (blk, net, gpu, input, console, rng, fs, sound) -> NVMe, AHCI,
xHCI + USB HID + USB storage + USB audio, e1000e/igc, Intel HDA -> one Wi-Fi
family and one real GPU family (chosen at M8).

Consequence, accepted: hardware support is narrow by design. The project names
one reference laptop and one reference server (chosen at M8) and supports those
completely. The public vendor documentation and the open-source drivers of
other systems are read as references for how the hardware behaves; their code
is not imported.

- Reason: restartable, sandboxed, and the kernel stays small.
- Escape hatch: class protocols are stable IDL, so a driver can be rewritten or replaced without touching anything above it.

## 8. Storage

- The data path is one crate for every device class (`silica_queue`): the two rings in a client's frame, the client's registered memory, the wake-up rule, the provider's session and a client that survives its provider (re-registering memory and resending what was in flight). A class adds only its records, the checks of a request against its device, and its control protocol; block was moved onto it when network became its second user.
- Block layer server with request rings. The class protocol (`silica.block.Device`, every block driver's and, for each partition, the block server's) carries only the control path as calls: what the device is, connecting, registering memory. Requests and completions travel through two rings in a frame the client shares (`silica_block` documents the layout), and their data stays in the client's frames, which the device reads and writes in place through the IOMMU: no copy between a filesystem and the disk, and a system call only when the other side said it sleeps. `silica_block::service` is everything a block driver shares (checking each request against the device and the registered memory before the driver sees it, the rings, the wake-ups, a client that went away), so a driver is what is specific to its hardware: virtio-blk is about 250 lines. A driver never trusts the rings' memory: a client that takes it back makes the driver read zeros (the device manager answers that fault with a zero page), which the ring reports as broken and the connection closes; no client can crash a driver.
- Native filesystem: copy-on-write, checksummed data and metadata, snapshots, transactional. Design is a simplified B-tree CoW layout; no in-kernel anything.
- Read-only content-addressed package store (Merkle-verified blobs).
- FAT32 (ESP, removable media), exFAT, and read-only ext4 and ISO9660 for interchange. These are native filesystem readers, not compatibility layers.
- Partitioning: GPT only.
- Full-disk encryption (AEAD per extent), key from TPM2 or passphrase.
- Verified boot: UEFI Secure Boot -> signed kernel -> Merkle-rooted system image. A/B slots with automatic rollback.

## 9. Networking

Userspace stack, one process per interface class, zero-copy rings to drivers.
IPv6-first with IPv4. TCP (with modern congestion control), UDP, QUIC as a
system service, ICMP, NDP/ARP, DHCPv4/v6, SLAAC, DNS resolver with DoT/DoH,
mDNS, TLS 1.3 only, NTP client with NTS, firewall as capability policy plus a
packet filter, WireGuard, Wi-Fi (WPA3) via supplicant service.

## 10. Graphics and the desktop

- The display class protocol (section 7) already has the compositor's shape: pixels in the client's memory, damage rectangles, no client mapping a driver's memory.
- Display server and compositor are one process. Protocol is a small native IDL protocol modeled on Wayland's object model (surfaces, buffers, frame callbacks, damage).
- Rendering API for apps: Vulkan-shaped. `wgpu` is the supported Rust API on top.
- M6 ships a **software** renderer (SIMD, tile-based, damage-tracked). Glass effect = dual-Kawase blur on downsampled backdrop + tint + noise + specular edge, cached per damage region. This runs on virtio-gpu 2D scanout and on bare GOP framebuffers.
- GPU acceleration arrives at M8 via virtio-gpu Venus first, then one native driver.
- Toolkit: retained-mode, declarative, GPU-agnostic scene graph; text via a Rust shaping + rasterization stack; accessibility tree mandatory in the widget trait from the first widget.
- Reason for software first: the UI is testable by screenshot in QEMU on day one, and no GPU driver sits on the critical path.

## 11. Software platform (no Unix, no shims)

Software is written for this OS. Nothing emulates POSIX, Linux, Wayland, or
any other system. Other languages are supported by making this OS a real
target for them, in four layers:

1. **One system interface, described once.** Every service is an IDL protocol. The IDL compiler generates bindings for Rust first, then C, C++, and further languages. A language talks to the OS directly through generated bindings.
2. **A C-ABI system library.** `libsys` plus the generated C bindings expose the native API (capabilities, endpoints, IDL protocols) in the C calling convention, which nearly every language runtime can call. It exposes this OS's concepts only: no file descriptors, no `fork`, no signals, no `errno`, no POSIX names.
3. **One LLVM target.** A target triple and a minimal freestanding C runtime (memory, math, startup, unwinding) give Rust, C, C++, Zig and Swift as native compiled languages. Each language's standard library gets a backend written against the native API.
4. **WebAssembly components.** The WASI component model is the route for Python, JavaScript, Go, C# and other managed languages, and the portable sandboxed app format. Its handles map one-to-one to capabilities.

Consequences, accepted:

- Existing Unix, Linux and Windows software does not run and is not ported by emulation. Software that depends on POSIX must be adapted to the native API by its porter.
- Browser: Servo, ported natively (Rust), at M7. Chromium is out of scope.
- Games: written for this OS against the native Vulkan-shaped API.
- Virtualization (`Vcpu`, M9) exists as a server feature for running guest operating systems in isolation. It is not a compatibility path and no desktop feature depends on it.

## 12. Languages, crates, license

- Rust, pinned nightly in `rust-toolchain.toml`. `no_std` in the kernel. Kernel logic lives in a `kernel-core` crate with no arch dependencies so it compiles and tests on the host.
- External crates are vendored (`cargo vendor`) and must be on this allowlist. Kernel: `bitflags`, `spin` (early boot only), `zerocopy`, `static_assertions`, `log`. Userspace: `hashbrown`, `smoltcp` (as a starting point for the stack; may be replaced), `rustls` + `ring` or `aws-lc-rs`, `wasmtime` or `wasmi`, `ttf-parser`, `rustybuzz`, `tiny-skia` (reference renderer for golden tests only), `serde` + `postcard`, `wgpu` (M8). Dev/test: `proptest`, `loom`, `kani-verifier`, `arbitrary`, `libfuzzer-sys`, `criterion`.
- Before adding a crate, measure its size cost and check its license; record both in the commit that adds it and extend this list.
- License: dual MIT / Apache-2.0. Permissive so vendors can ship it; governance and a trademark, not copyleft, protect the project.

## 13. Security baseline

Capabilities everywhere. W^X enforced by the kernel. KASLR and userspace ASLR.
SMEP/SMAP/UMIP, CET shadow stacks and IBT where present (PAC/BTI on arm).
Speculative-execution mitigations chosen per CPU at boot: enhanced IBRS and BHI_DIS_S where the processor has them, buffer clearing (VERW) on return to user mode where it is affected by MDS or RFDS, a barrier after every conditional `swapgs`; there is nothing to sanitize for Spectre v1 because the kernel takes no user pointers. A processor that would need retpolines or kernel page-table isolation (no enhanced IBRS, or affected by Meltdown) is reported at boot as unprotected and is not supported hardware. DMA confined by the IOMMU on every machine that has one; a machine without one is named as such at boot and its
DMA-capable drivers are trusted (section 6). One kernel stack per processor with a guard page (section 6). No
`unsafe` outside the modules listed in `spec/UNSAFE_MODULES.md`. Measured
boot into TPM2. Per-app sandbox is the default, not an option.

## 14. Observability and operations

Structured logging service, tracing with static tracepoints, per-process-tree resource
accounting, crash dumps to a dedicated partition, a kernel debugger stub over
serial, remote management over an authenticated native protocol (the SSH
equivalent), service manager with dependency graph and restart policy.

## 15. Driver porting method

Drivers are translated into native Rust, never wrapped. The goal is the same
throughput and latency as the best existing driver for that device.

1. **Reference.** Pick the best open driver for the device from any system, plus the vendor's public documentation. These describe how the hardware behaves.
2. **Behavior description.** Read the reference and write `drivers/<name>/BEHAVIOR.md`: register map, initialization sequence, queue and interrupt model, power states, error recovery, known quirks. Register definitions go in a machine-readable file from which accessor code is generated.
3. **Implementation.** Write the Rust driver from the behavior description and the class framework, with the reference closed. This keeps the driver idiomatic to this OS instead of a line-by-line copy of another system's structure.
4. **Class framework.** Everything common to a device class is written once in `drivers/framework/<class>`: queue management, DMA mapping, interrupt handling, power transitions, reset and recovery, statistics. A driver contains only what is specific to its hardware. Target: a new driver in an existing class is under 3,000 lines.
5. **Performance by design.** Direct MMIO mapping; shared-memory rings with zero copies between driver and its consumer; batching; interrupt mitigation with a switch to polling under load; per-queue threads pinned to cores; huge-page DMA pools. A driver and its immediate consumer (NIC and network stack, NVMe and block server) may be linked into one process when measurement shows the IPC hop matters; the class protocol stays the same either way.
6. **Verification against the reference.** For each driver: (a) run the reference driver and ours against the same device (emulated first, real hardware at M8), record the register traces, and compare initialization and steady-state sequences; (b) fault injection through the mock-device framework; (c) benchmark against the reference on the same hardware. Gate: at or better than the reference on throughput and p99 latency, or the driver is not done.
7. **Order of work.** Standard class drivers first (one driver covers every conforming device), then the parts of the two reference machines, then by community demand.
8. **Finished.** A driver that passes its happy path in QEMU is a prototype. A finished driver negotiates features, handles every feature it accepts and relies only on behaviour the specification guarantees, because an emulator is more forgiving than hardware. It recovers from device errors, timeouts and resets, and a request outstanding during a restart completes or fails cleanly with nothing leaked. Its DMA is confined by the IOMMU and it holds no authority beyond its device. Its throughput and tail latency meet the gate in item 6. It reports link, media, error and statistics state in a form the owner can read. Where only emulated devices were available, the driver's documentation names the device models it was verified against and what still needs a physical machine; that is not described as hardware support.

## 16. System management

How the system is installed, composed, updated and extended. The rule
throughout: nothing mutates shared global state, so nothing can break
something else.

- **Base system.** One read-only, signed, verified image containing the kernel, core services and system libraries. Updated as a whole into the inactive slot, switched atomically, rolled back automatically if the new slot fails to boot healthy.
- **Packages.** Everything outside the base, including apps, drivers, language runtimes, fonts and codecs, is a package: an immutable, content-addressed, signed bundle with a manifest declaring what it provides and which capabilities it requests. Installing is fetch plus verify. There are no install scripts and no post-install hooks. Removing a package leaves nothing behind. Any number of versions coexist.
- **Libraries.** There is no global library directory and no system-wide library version resolution. The stable system API is the IDL protocols plus `libsys`. Every package carries the libraries it was built with. Storage is content-addressed, so identical files across packages are stored once and their pages are shared in memory once. This gives the reliability of static linking with the footprint of shared libraries. Each package carries a machine-readable list of its components so a vulnerable library can be found in every package that contains it.
- **Drivers as packages.** A driver package's manifest lists the device identifiers it binds to. The device manager matches and starts it in its sandbox. Drivers update independently of the base system because the class protocols are stable. A crashing driver is restarted; a driver that crashes repeatedly is rolled back to its previous version.
- **Services.** Declared in manifests: what they provide, what they need, restart policy. The service manager builds the graph and routes capabilities. Nothing starts by script.
- **One description of the machine.** A single typed, versioned document states the base version, the installed packages, the settings and the users. Applying it is transactional. Every change creates a generation; any earlier generation can be booted. The same document on identical hardware produces an identical system.
- **App data.** Each app sees only its own storage plus whatever the user grants through the system file picker. Uninstalling offers to keep or remove that data.
- **Permissions.** An app starts with the capabilities in its manifest that the user approved, and nothing else. Grants are visible and revocable in one place.
- **Builds and distribution.** Builds are reproducible. Packages are signed and recorded in a public append-only log. Repositories are plain static files, so anyone can mirror or host one.

## 17. Project and community

- **Stable interfaces.** IDL protocols are versioned and, from the first `stable` release, evolve additively, each change with a written rationale.
- **One set of gates.** Every change, from any contributor, passes the same automated tests, size budgets and performance gates.
- **Driver kit.** Class frameworks, the mock-device test rig, a template, and a guide, so a hardware vendor or volunteer can ship a driver package without touching the base system.
- **Supported hardware list.** Short and honest: the reference machines are fully supported; everything else is listed with exactly what works.
- **Documentation generated from source.** The IDL reference, the architecture book and the driver guide build from the repository and fail the build when out of date.

## 18. How components connect

Most of what makes a system pleasant or miserable lives in the seams: how a driver meets its class protocol, how a
service finds the services it needs, how an application receives the capabilities it was granted, how a new
device, package or update joins a running system. Each seam is decided on purpose, before the code on either side,
and written into the protocol:

- **Discovery.** How each side finds the other, and what the owner sees when it cannot.
- **Authority.** Which capabilities cross, who grants them, and how they are revoked. The default is the least that does the job.
- **Lifecycle.** Start order, readiness, restart, upgrade and removal, and what the other side observes during each.
- **Failure.** What every error means, who recovers, and what state survives.
- **Versioning.** How an older and a newer side keep working together.
- **Cost.** Copies, round trips and wakeups per operation, measured.

One mechanism serves each of these across the whole system. A driver, a service and an application are declared,
started, granted authority, observed and updated in the same way, so learning one teaches the rest. Every special
case at a seam is something each later author and administrator has to learn, and a place where policy can be
bypassed.

Each seam is judged by the people on the outside of it:

- **The driver author** has a device, its datasheet and a weekend. They discover what the class protocol expects, write only what is specific to their hardware, see why a request failed, and survive their own crashes without rebooting.
- **The application author** has the published bindings and the examples, and nothing else. Nothing existing runs on Silica, so the cost of writing or porting a program is the cost of the system's future.
- **The owner** opens the hood: lists every process and what it may touch, reads every log, traces a request across services, scripts the system from a shell and swaps any component. Typed protocols are as inspectable from the command line as text files were.
- **The end user** plugs in a device, installs an application or accepts an update, and it works. A decision that is theirs is asked once, in plain words, and can be undone in one obvious place.
- **The company** describes a machine in one document and gets the same system every time, applies policy about what may run and what it may touch, rolls updates out and back, sees what every machine runs and which capabilities each component holds, and relies on interfaces staying compatible for years.

Security, stability and ease come from the structure. The safe path is also the shortest path for an author, or it
will be skipped. When ease of use seems to need a broader grant, a hidden global, a compatibility shim or another
daemon, that is a design problem to solve within the size budgets.
