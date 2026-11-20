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

- **Objects (10, final)**: Untyped, CapSpace, Thread, AddressSpace, Frame (memory, any power-of-two size from a page up), Endpoint (synchronous IPC), Notification (async signal, also carries interrupts), SchedContext (CPU budget), Hw (a range of hardware resources that are not memory: I/O ports or interrupt lines, created at boot and only ever narrowed), Vcpu (M9). There is no Channel, Port, Timer, Interrupt, PageTable or Job object: each is either expressed with these ten or lives in userspace.
- **Untyped memory**: all physical memory is handed to the root task as Untyped capabilities at boot. Every kernel object is created by retyping Untyped memory that the caller owns. The kernel has no heap and never allocates after boot. Resource accounting, quotas and "jobs" are therefore userspace policy with no kernel code. Revoking an Untyped destroys everything made from it.
- **Capabilities**: unforgeable handles with a rights mask, named by slot index in the caller's CapSpace (one flat table per CapSpace, no guards or multi-level addressing; an operation on another CapSpace names that CapSpace's capability and an index). Every capability has a place in a derivation tree. *Derive* makes a child with equal or fewer rights that depends on its source; *duplicate* makes an independent sibling; *move* keeps the place. A capability never outlives what it was derived from: deleting one deletes its descendants, so no descendant is ever re-parented and every step of delete and revoke is O(1) and preemptible. Lend with derive, hand on with duplicate or move. An Untyped has exactly one capability (split it by retyping). No capability, no access. No exceptions.
- **Kernel execution**: one kernel stack per processor with a guard page, interrupts off in the kernel, no blocking inside it. Every entry runs to completion and returns to the thread the scheduler picks. Long operations (zeroing a large Retype, revoking a large tree) poll for a pending interrupt, record their progress in the objects, and restart. The kernel never dereferences a user virtual address: message words beyond the registers travel through the thread's IPC buffer Frame, reached through the kernel's map of physical memory. A system call preserves what a function call preserves (callee-saved general registers and the floating-point control words) and, like a function call, not the vector registers; so a thread switched out inside a system call needs no extended-state save, and when it resumes its vector registers are cleared. Interrupted and faulted threads get a full save and restore. The scheduler runs on the way out only when an entry changed something it cares about.
- **IPC**: synchronous call/reply on Endpoints with direct thread switch (a call runs the waiting receiver at once, its reply runs the caller at once, both inside the caller's time slice) and register passing; capabilities and Frames transferred in the message. Streams, channels, ports and shared submission/completion rings are userspace libraries built from Frames plus Notifications. The kernel knows nothing about them.
- **Memory**: userspace pagers handle faults (a fault is a call to the thread's fault endpoint; the reply resumes it, and can carry the frame to map so the usual cure costs one kernel entry). An AddressSpace object carries the memory for its own page tables and `Map` fails with `NoMemory` when that runs out, so table memory is paid for by the owner like everything else. One Frame capability maps at one place; copy it to map it twice. Deleting a Frame capability, or the address space, removes the mapping. No mapping is writable and executable at once. Frames of 2 MiB and up use large pages. No overcommit, no OOM killer; allocation fails at the caller.
- **Scheduler**: per-CPU run queues; EEVDF-style fair class plus a deadline class with admission control; scheduling-context capabilities so budget is delegated across IPC (priority-inheritance by construction); core-type aware (P/E cores); tickless.
- **SMP**: per-CPU kernel data, no big kernel lock, lock ordering documented and checked under `loom`.
- **Time**: monotonic clock from the invariant TSC (or arch equivalent), calibrated from CPUID, the hypervisor's clock, or the ACPI PM timer; read in userspace without a syscall. There is no timer object: a receive takes an absolute deadline, so a sleep is a wait on a notification nobody signals and a timeout is the same call. Wall clock is a userspace service.
- **Interrupts**: MSI/MSI-X preferred, IOAPIC line interrupts supported (GICv3 on arm); every interrupt is bound to a Notification.
- **HAL**: `kernel/arch/{x86_64,aarch64,riscv64}` behind one trait. x86_64 is built first; aarch64 must compile and boot by M2 so the trait stays honest.

Escape hatch: object set and rights are versioned in `libsys`; adding an object type is additive.

## 7. Drivers

Userspace processes. Each gets: MMIO Frame caps (and IoPort caps where the device needs them), Notifications bound to its interrupts, an
IOMMU domain, and nothing else. A driver host supervises and restarts them.
Driver interfaces are IDL protocols per class (block, net, display, input,
audio, usb-host, gpu).

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

- Block layer server with request rings.
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
Speculative-execution mitigations chosen per CPU at boot: enhanced IBRS and BHI_DIS_S where the processor has them, buffer clearing (VERW) on return to user mode where it is affected by MDS or RFDS, a barrier after every conditional `swapgs`; there is nothing to sanitize for Spectre v1 because the kernel takes no user pointers. A processor that would need retpolines or kernel page-table isolation (no enhanced IBRS, or affected by Meltdown) is reported at boot as unprotected and is not supported hardware. IOMMU mandatory for
any DMA-capable driver. One kernel stack per processor with a guard page (section 6). No
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
6. **Verification against the reference.** For each driver: (a) run the reference driver and ours against the same device (emulated first, real hardware at M8), record the register traces, and compare initialization and steady-state sequences; (b) fault injection through the mock-device framework; (c) benchmark against the reference on the same hardware. Gate: within 10% of the reference on throughput and p99 latency, or the driver is not done.
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
