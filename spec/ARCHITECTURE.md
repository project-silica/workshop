# Silica architecture

The current design: what each part promises, and why. It is open to challenge on evidence (`AGENTS.md`); change it
in the same work as the code that shows it wrong. Measurements and history live in commit messages, not here.

## Invariants

Every component keeps these. A design that seems to need an exception is a design problem to solve.

1. **Least authority, carried by the capability.** A holder can do what its capability's rights and scope say and
   nothing more, so a compromised component reaches only what it was given.
2. **Every resource a less-trusted party can consume is bounded per holder and reclaimed when the holder goes**
   (slots, connections, windows, queue entries, rings, memory, processor time, time holding locks), so no client
   can exhaust a service for the others.
3. **Nothing waits forever on something it trusts less.** Calls into drivers and peers carry time limits and a dead
   peer is noticed, so one hung component cannot hang the ones above it.
4. **Less-trusted input never changes what a more-trusted part believes unchecked** (time, routes, neighbours,
   leases, versions, device state), because the belief outlives the input.
5. **The first holder keeps what it holds.** A second claimant is refused, never silently substituted, so a holder
   of an endpoint cannot take over someone else's session.
6. **Untrusted bytes are decoded totally and shown inertly.** Parsers never panic and control characters never
   reach a terminal, because every boundary is an attack surface.
7. **Fail closed and say why.** An unknown field, an unsupported feature or an unconfined device is refused or
   reported by name, never ignored, so nobody believes a promise that was not kept.
8. **Secrets live only where they are needed and are wiped after use**, so a component that leaks reveals no more
   than it holds.
9. **A cost an adversary can trigger is a security bug, not a performance limit**, because the attacker chooses
   the workload.
10. **A guarantee beats a number.** When a guarantee costs speed, record the cost with its reason
    (`os/bench/open.tsv`) and win it back in the design; never trade the guarantee.

Performance aims at each path's own best, not at a margin over another system: a path is tuned until a profile shows
that what remains is work the hardware or a guarantee requires, and every improvement becomes its new ratchet.
Linux's numbers are a floor to stay above (`spec/TESTING.md` section 4.1).

Every trust boundary (syscall, IDL method, parser of untrusted bytes, device response) has its promise written beside
the code and an attack test that fails when the promise breaks.

## 1. Shape

A capability microkernel (seL4 lineage: fewer object types, fewer syscalls, no kernel heap, no policy in the kernel;
from Zircon only what costs no kernel code). Everything else runs in isolated userspace programs that talk over typed
IPC, because only that gives small size, restartable drivers and isolation at once.

- 64-bit only (no 32-bit kernel, userspace, compat mode or entry).
- No legacy hardware interfaces or Unix conventions (section 3); older but common hardware (SATA, I/O ports, line
  interrupts) is supported.
- No compatibility layers, shims or emulation of other systems, in the kernel or above it (section 11).
- Escape hatch: the syscall surface is private (section 4), so servers can be merged later without changing apps.

## 2. Size budgets (enforced by `tools/size.sh`)

| Artifact | Budget | Required from | Rationale |
| --- | --- | --- | --- |
| IPC fast path + context switch + syscall entry | 32 KB text | M2 | fits L1i |
| Kernel image, text + rodata | 256 KB | M1 | fits L2 on any CPU since 2015 |
| Kernel + core servers (init, memory, process, vfs, net, block) resident text | 2 MB | M5 | fits L2 on current desktop/server CPUs, L3 everywhere |
| Minimal server image (boots, serves TCP, SSH-equivalent) | 16 MB on disk | M4 | measured as the bytes of its files (`build_server_image`) |
| Desktop image without browser | 128 MB on disk | M6 | |

From its milestone on, a missing artifact fails `tools/size.sh`; before that it is skipped. The images measured are
the files the exit test boots.

| Bloat ceiling (from M1) | Ceiling |
| --- | --- |
| Kernel source, excluding tests and the three arch directories | 12,000 lines of Rust |
| Each arch directory | 4,000 lines |
| Syscalls (every kernel operation is its own syscall) | 32 |
| Kernel object types | 10 |
| Heap allocations inside the kernel after boot | 0 |

A change that breaks a budget is not finished. Raise a budget only with the measurement written beside the number.

## 3. What is deleted

| Legacy abstraction | Replacement |
| --- | --- |
| `fork`/`exec` | `spawn(image, capabilities)`: the child gets only what the parent hands over |
| Ambient authority, uid/gid, root | Capabilities only; users are a policy service |
| Global filesystem namespace | Per-program namespace built from directory capabilities |
| Signals | Typed messages; faults delivered to a supervisor's endpoint |
| `ioctl`, "everything is a file" | Typed IDL protocols on typed objects |
| Blocking I/O syscalls | Shared-memory rings; a synchronous call is a library wrapper |
| TTY/PTY line discipline | A terminal protocol over a channel |
| BIOS, CSM, MBR, PIC, PIT, xAPIC, PS/2, VGA text, IDE, ISA | UEFI, GPT, x2APIC, TSC-deadline on an invariant TSC, USB HID, GOP, NVMe/AHCI/virtio |
| Kernel heap, kernel modules | Untyped memory supplied by userspace; restartable userspace drivers |
| `/etc`, in-place installs, setuid/sudo | One typed config store; content-addressed A/B updates; delegation through a broker with consent |

x86_64 requires x86-64-v3 (what user programs are built for), NX, x2APIC, XSAVE and an invariant TSC; aarch64 user
programs are Armv8.0 and PAN is used where present. The loader and kernel refuse an unsupported processor by name
(`inos.*/cpu.*`). Kept because firmware or the internet need them, all outside the kernel: FAT32 for the ESP, ACPI,
IPv4 beside IPv6.

## 4. Stable ABI

Syscall numbers are private and never called by applications. The stable contract is the IDL protocols in `idl/`
(additive evolution, `spec/IDL.md` section 4) and `libsys`, mapped into every program. Before the first `stable`
release (`spec/CI_RELEASE.md` section 8) protocols are provisional and replaced by staged migration: add the new one,
move the provider and every consumer, remove the old one, each commit building. From the first `stable` release,
nothing published is removed or changed. Reason: this lets the kernel be rewritten under running software.

## 5. Kernel contents

Address spaces and page tables, threads, scheduling, capabilities, IPC (call/reply, notifications, shared memory),
interrupt routing to userspace, timers, IOMMU programming, exception delivery, boot handoff. Nothing else: no
filesystems, network stack, drivers (beyond the interrupt controller, timer and early serial), process, naming or
security policy.

## 6. Kernel mechanisms

- **Objects (10, final):** Untyped, CapSpace, Thread, AddressSpace, Frame, Endpoint, Notification, SchedContext, Hw
  (ports, interrupt lines, device identities, console, power: only ever narrowed), Vcpu (M9). Channels, ports,
  timers and rings are userspace built from these.
- **Untyped memory:** all memory reaches the root task as Untyped; every object is retyped from memory its caller
  owns; no kernel heap. Revoking an Untyped destroys everything made from it, so accounting and kill are userspace.
- **Capabilities:** a rights mask and, on endpoints and notifications, a badge set once by the minter and never
  changed by a holder (so a provider trusts the badge as the caller's identity and scope). Derive makes a child with
  equal or fewer rights; duplicate an independent sibling; move keeps the place. Deleting a capability deletes its
  descendants; every step of delete and revoke is O(1) and preemptible. Each operation checks the rights the use
  needs (`ThreadConfigure`, `Inspect`, `IrqBind`, `IrqWatch`: `kernel-core/tests/hostile.rs`). `CapNotice` tells a
  holder when one of its capabilities goes, by whatever means, without a kernel table anyone can fill.
- **Execution:** one guard-paged stack per processor, interrupts off, no blocking. Long operations (reaping a
  CapSpace: every 256 slots; one `Map` or `Unmap`: at most `MAP_MAX_ENTRIES` = 2^15 entries) stop for a pending
  interrupt and resume, so no single call holds the machine. The kernel never dereferences a user address. A
  syscall preserves what a function call does and not the vector registers; `ThreadStart` resets the saved vector
  state.
- **IPC:** synchronous call/reply on endpoints with direct switch; up to 500 words and four capabilities, each lent,
  duplicated or given (GRANT needed to send them). A call may carry a time limit (`CALL_TIMEOUT_SHIFT`): past it the
  call fails with `Timeout` wherever it waits and a late reply goes nowhere. An operation is tied to the capability
  it was made through: when that capability leaves its slot, the operation fails with `Gone` (revoking a client stops
  it now). A receive may also listen on a notification (`MsgInfo::NOTIFIED`, which no message can imitate): the
  one-thread event loop of every driver and server (`silica_rt::ipc::serve_events`). A received message's length is
  checked against the words the kernel delivered.
- **Memory:** faults are calls to the thread's fault endpoint (pagers in userspace). An address space pays for its
  own page tables; tables whose mappings are gone return to its pool. `Unmap` of an address space (write right)
  clears a range whoever's frames are in it, so a program can reuse addresses where lent memory was. No mapping is
  writable and executable. No overcommit: allocation fails at the caller.
- **Scheduler:** per-processor queues; a fair class (virtual runtime by weight) and a deadline class (admitted up to
  90% of a processor, earliest deadline first). Processor time is a capability (`SLOT_SCHED`): a weight above the
  default, a reservation or a group needs authority over the processors concerned. Fair scheduling has two levels:
  a group (`SCHED_GROUP`) takes one share of its processor however many threads it holds, a thread made by a grouped
  thread stays in the group, and the service manager gives every service one (`a_program_with_many_threads_takes_one_share`).
  The fair queue and the timers are AVL trees (`order.rs`), so a wake-up costs the same beside thousands of threads.
  IPC donates the caller's share to the server. Tickless.
- **SMP:** every thread has a home processor; moving it is explicit and invisible to it. One lock per processor:
  local, pair (two processors in index order), structure (mapping), and global (every lock: capability slots,
  unmapping, other processors' threads). A processor may hold every lock for a tenth of the machine's time divided
  among the processors (`GLOBAL_SHARE`, after a 5 ms burst); past it a call waits (`THROTTLED`), so a program
  flooding capability operations cannot stop the others (`smp_global_flood`). A destroyed address space's memory is
  reused only after every processor that had it loaded has left it. Modelled under `loom`.
- **Boot:** the kernel checks the whole boot archive (CRC32C and every format rule, one reader shared with the image
  builder) before starting the root task; a damaged archive runs nothing (`error.archive_damaged`). Secondary
  processors are counted as they arrive, their TSC checked against the boot processor's. Machine checks are
  handled (a program's uncorrected error is its fault); NMIs are counted; a panic stops every processor. The boot
  is refused without a trusted entropy source unless the owner says `entropy=accept` (`cpu.no_rng`).
- **Randomness:** every program has its own ChaCha20 generator with fast key erasure, seeded by its parent; the root
  task's from the boot secret, which reaches it in registers and is kept only in its own memory (no frame it lends
  holds it).
- **Logs:** each service writes a ring of its own without waiting; `logd` keeps and shows them, and never waits on
  the service manager. A service may register at most half the machine's 64 log rings, named after itself; rings
  whose maker ended are reclaimed. Text shown on a terminal goes through `silica_rt::text::printable`.
- **Providers that restart:** a service hears on its events notification when a provider it needs started again. A
  service that `keeps` has a page kept across restarts and replaced with an empty one when its program changes.
  A provider that stops answering is ended and started again: a client whose time-limited call to it expired tells
  the service manager, which probes it once (every runtime answers the probe from its request loop); nothing polls.
  Services build with overflow checks in release, as the kernel does: arithmetic that would wrap stops the program,
  and its supervisor starts it again.
- **Console and power:** the kernel's console never waits for the port (a ring fed as the UART takes it; a piece
  that does not fit is dropped and said). The power capability turns the machine off or resets it (PSCI; ACPI S5
  and the reset register). The QEMU debug-exit port is written only when the command line names a harness
  (`exit=port`).
- **Time:** a monotonic clock read in userspace; no timer object (a receive takes a deadline). The wall clock is a
  page every program reads; only a service declared `sets_time` may write it. Readers give up on a writer that
  stopped mid-update and report the time unknown.
- **Interrupts:** bound to a notification and delivered on the processor of the thread waiting on it; the kernel
  moves the line when that thread moves (remapping entry, I/O APIC, GIC route or ITS collection; `irq_follow`). A
  level-triggered line is held off until acknowledged. With interrupt remapping a device raises only the lines its
  driver bound (`rogue_tcg`). A failed `IrqBind` leaves the old binding as it was. `IrqWatch` lets an idle processor
  see a device's completion word before its interrupt.
- **Placement:** work follows the request, not the service. A request stays on the processor where it arrives,
  device interrupt to driver to stack to program, or at least in one cache domain: each crossing costs a wake-up
  and cache misses. Throughput scales by a path per processor, not by moving services: `silica-queue` gives a
  client a queue per processor it submits from, a device a hardware queue per processor where it has them, and the
  completion's line follows its waiter. The management plane (service manager, log, device manager, remote
  management) runs on a housekeeping processor, the data plane beside its devices. A declaration states a role and
  a device to be near (`cpu=` pins only where a measurement says so); the service manager maps it onto the
  machine's topology, which the kernel gives the root task in its start record. A balancer is an ordinary service
  holding the processor-time capability: the kernel signals sustained imbalance as an event, and the balancer moves
  scheduling groups; nothing polls, so an idle machine wakes nothing. Mechanism only in the kernel (topology, the
  imbalance event, lines following waiters); policy only in services. No placement file, boot parameter or tuning
  knob, and no kernel thread: authority over processors is the processor-time capability and nothing else.
- **Devices and DMA:** a device reaches exactly what is mapped in its device address space (`ASPACE_IO`), nothing
  before it is attached and nothing after the space goes; `Unmap` returns after the IOMMU dropped the translation.
  Confinement is for every device or none: a unit the kernel cannot drive makes it refuse every `DeviceAttach` and
  say no device is confined. An unresponsive unit stops the machine naming it. Without an IOMMU (`iommu=off`)
  `DeviceAttach` is `Unsupported`, the boot says so, and starting a DMA-capable driver is trusting it (`unconfined`).
- **Speculation:** an address space can be isolated (`ASPACE_ISOLATED`): switches into and out of it flush the
  predictors and set STIBP and SSBD. Meltdown-affected processors are refused unless the owner says `meltdown=accept`.
- **Inspection:** `Inspect` (read right) reads slots, threads, interrupt lines and parked calls; the owner's tools use
  the owner's capabilities, and there is no kernel debugger with authority of its own.
- **HAL:** `kernel/arch/{x86_64,aarch64,riscv64}` behind one trait; aarch64 boots the same tests.

**Programs.** A program is what its parent makes with `silica-proc` from one Untyped: CapSpace, address space, first
thread, image and start-up record. It holds only what its parent listed, ends by telling its parent, and is taken
back by revoking that Untyped. A failed spawn returns what was given outright. A supervisor answers a fault on lent
memory the lender took back with a page of zeros, recycling a bounded pool, so a service never dies of a client
ending (`lent_memory_taken_back_any_number_of_times`).

**Calls between programs.** One IDL message is one kernel message. A provider learns who calls from the badge of the
caller's capability, which the caller cannot change; scopes in the badge (`silica_protocols::scope`) say what of a
protocol the caller may use.

## 7. Drivers

Userspace programs, each holding its device's identity, interrupt lines, configuration space read-only, its memory
BARs and its own IOMMU domain, and nothing else. Class protocols per device class in IDL; a class framework holds
what all drivers of a class share, so a driver holds only what is specific to its hardware.

- **The seam** (`silica_driver`'s documentation is the contract): the device manager owns configuration space and
  switches decoding, bus mastering and MSI-X on before a driver runs and off when it ends or fails to start.
- **Restarts:** a driver that faults or fails is destroyed, its device silenced, and restarted by
  `silica_proc::Restarts` (at once, then backing off to one try a minute, never given up for good). An owner's
  `restart` is not counted. A clean `EXIT_AGAIN` is a deliberate restart, not a failure.
- **Clients survive their driver:** `open` takes a notification signalled when the driver ends; `silica_queue`
  clients drain completions, reconnect without spinning, re-register memory and resend what was in flight. A flush
  after a driver ended with unflushed writes reports them lost, so a program never believes them durable.
- **One client keeps its device:** input, display and console port refuse a second `connect`/`attach` while the
  first client lives (`in_use`).
- **Devices misbehave:** a driver checks every completion, refuses queues too small for one request, watches
  `DEVICE_NEEDS_RESET`, negotiates every feature it uses, gives requests a deadline (30 s, 1 s with a fault armed)
  and otherwise ends to be restarted. `inject=<driver>:<fault>@<n>` commits a device's faults on purpose (`faults`).
- **Clients cannot break the device for others:** memory of a connection that ended stays mapped until its last
  request completes; events never take a completion's ring slot; device addresses of released memory are reused.
- **Hostile drivers:** `virtio-rogue` holds exactly what a driver holds and every attempt beyond it must fail
  (`rogue`, `rogue_tcg`, `rogue_net`).
- **Hot-plug:** the device manager arms PCIe hot-plug ports, powers slots, places BARs within the port's windows and
  starts drivers; removal ends them and powers the slot off (`hotplug`).
- Every driver is native Rust against the class protocols; no wrapper for another system's drivers. Order: virtio,
  then NVMe, AHCI, xHCI/USB, e1000e/igc, HDA, then one Wi-Fi and one GPU family (M8). Hardware support is narrow by
  design: one reference laptop and one reference server, supported completely.

## 8. Storage

- One data path for every device class (`silica_queue`): two rings in a client's frame, data in the client's own
  memory read and written in place by the device through the IOMMU, a system call only when the other side sleeps.
  A dropped client ends its connection.
- **The block server** (`partitions`) is on the way to a partition, not on its requests: it reads each disk's GPT
  (both checksums, in transfers within the device's limits), re-reads it when a disk's driver changes, and `open`
  returns a capability narrowed to the partition. Narrowed windows are deduplicated by range and bounded per holder;
  a flush through a partition flushes only when a write needs it. Its scopes: `list`, `open`.
- Planned (M5): a copy-on-write checksummed native filesystem, a content-addressed package store, FAT32/exFAT and
  read-only ext4/ISO9660 readers, GPT only, AEAD full-disk encryption keyed by TPM2 or passphrase, verified boot with
  A/B slots and rollback.

## 9. Networking

A userspace stack (`netd`, wire formats in `silica-inet`: parsers over `&[u8]` that check every length and checksum
and allocate nothing). IPv6-first with IPv4; planned: UDP for programs, QUIC, DNS with DoT/DoH, TLS 1.3 only, NTS,
a packet filter, WireGuard, Wi-Fi.

- **DHCP** is answered only from the chosen server and leases that cannot be used are refused. **ARP** learns only
  what it asked and never evicts the router for a stranger. **SNTP** asks with a random nonce from a random port and
  believes an answer only when its times are possible, its round trip is under 1 s and, once set, it moves the clock
  under 1000 s. A lease that changes ends the connections on the old address.
- **TCP for programs** (`silica.net.Tcp`): a program lends memory once and names a block of it per connection; bytes
  travel in two byte streams in that block. The stack never waits on a program; connections belong to the program
  that made them and end when it does. Each program has at most 128 of the 256 connections; a listener's full
  backlog evicts its own oldest half-open handshake; TIME-WAIT holds a small record restarted only by the peer's own
  FIN; FIN-WAIT-2 ends when nobody holds the connection and the peer is silent; timestamps do not reveal uptime; a
  receiver that answers zero-window probes is kept. Transmit rotates between connections, connections with work are
  marked due and segments find their connection through an index. The device's transmit offloads are used where
  offered (`silica.net.Device` version 3).
- Tests: `inet/tests/tcp.rs`, fuzz targets `frames` and `tcp_peer`, the interop suite against the host's Linux stack
  over a tap with hostile cases (`interop`: forged ARP, SYN flood, TIME-WAIT churn), `tcphog`, `http_load`,
  `http_restart`, `ntp`, `dhcp`.

## 10. Graphics and the desktop

- The display class already has the compositor's shape: pixels in the client's memory, damage rectangles.
- Display server and compositor are one process, with a small native protocol modelled on Wayland's object model.
- Apps render through a Vulkan-shaped API (`wgpu` on top). M6 ships a software renderer (SIMD, tiled,
  damage-tracked) so the UI is testable by screenshot in QEMU without a GPU driver; GPU acceleration at M8
  (virtio-gpu Venus, then one native driver).
- A retained-mode toolkit with an accessibility tree in the widget trait from the first widget.

## 11. Software platform

Software is written for this OS; nothing emulates POSIX, Linux or Wayland. Languages reach the OS through:
(1) IDL-generated bindings, Rust first; (2) a C-ABI `libsys` exposing only this OS's concepts; (3) one LLVM target
with a minimal C runtime (Rust, C, C++, Zig, Swift) and standard-library backends on the native API; (4) WebAssembly
components (WASI) for managed languages, handles mapping one-to-one to capabilities. Browser: Servo, natively (M7).
Virtualization (`Vcpu`, M9) is for isolated guests, not compatibility.

## 12. Languages, crates, license

- Rust, pinned nightly in `rust-toolchain.toml`; `no_std` in the kernel; kernel logic in `kernel-core`, testable on
  the host.
- External crates are vendored and on this allowlist. Kernel: `bitflags`, `spin` (early boot only), `zerocopy`,
  `static_assertions`, `log`. Userspace: `hashbrown`, `smoltcp`, `rustls` + `ring` or `aws-lc-rs`, `wasmtime` or
  `wasmi`, `ttf-parser`, `rustybuzz`, `tiny-skia` (golden tests only), `serde` + `postcard`, `wgpu` (M8).
  Dev/test: `proptest`, `loom`, `kani-verifier`, `arbitrary`, `libfuzzer-sys`, `criterion`. Adding one records its
  size cost and license in the commit and extends this list.
- No `unsafe` outside `spec/UNSAFE_MODULES.md`. No Python anywhere.
- License: dual MIT / Apache-2.0.

## 13. Security baseline

Capabilities everywhere; W^X; KASLR and ASLR; SMEP/SMAP/UMIP, CET and PAC/BTI where present; speculative-execution
mitigations chosen per processor at boot (section 6). DMA confined by the IOMMU (section 6). Measured boot into TPM2
and per-app sandboxes by default (M5). The threats each boundary must withstand are the invariants above, each tested
by attacking it.

## 14. Observability and operations

Structured logs, static tracepoints (`trace` across client, block server and driver), `log` and `caps` in the shell,
crash dumps (planned), and a service manager with a dependency graph and restart policy.

- **Remote management** (`remote`, `silica.remote.Session`): a session carries the IDL requests a local program would
  make to the service manager and the log, so a script or agent elsewhere can do what the shell can. Noise IK
  (`Noise_IK_25519_ChaChaPoly_BLAKE2s`, `silica-crypto`, checked against RFC and Noise vectors), no algorithm
  negotiation. An owner's first message carries a stamp newer than its last, so a replayed handshake opens nothing;
  only whole messages keep a session alive (`remote.idle=`); unproven connections get eight places, two per
  address, 10 s; each owner holds its own scopes; a refused stage takes no lock. Keys and secrets are wiped after
  use. The machine key ships in the image today; made on the machine at first boot is owed with storage (M5).
- **Updates while running:** `stage` then `update` runs a service on a new program checked as an ELF image; a program
  that fails within 10 s is replaced by the one before; `revert` returns to the boot archive's; `list` shows each
  program's BLAKE2s.
- **Service manager scopes** (`silica.system.Manager`): `observe`, `control`, `update`, `power`, `logs`, carried in
  each service's badge from its declaration (`needs=<protocol>:<scope>+<scope>`) (`svcload` attacks them).
- **Server image:** `build_server_image` holds init, the boot services and the drivers, and nothing that tests the
  system (`server_image`).

## 15. Driver porting method

Drivers are written natively, never wrapped; the goal is the throughput and latency of the best existing driver.

1. **Reference:** the best open driver for the device and the vendor's public documentation.
2. **Behavior description:** `drivers/<name>/BEHAVIOR.md`: registers, initialization, queues and interrupts, power,
   error recovery, quirks; registers in a machine-readable file that generates accessors.
3. **Implementation** from the description and the class framework, the reference closed.
4. **Class framework** holds everything common to a class; a new driver in an existing class is under 3,000 lines.
5. **Performance by design:** direct MMIO, zero-copy rings, batching, interrupt mitigation with polling under load,
   per-queue threads, huge-page DMA pools; a driver and its consumer may share a process when measurement says so.
6. **Verification:** register traces against the reference, fault injection, and a benchmark on the same hardware:
   at or better than the reference on throughput and p99, or the driver is not done.
7. **Order:** standard class drivers, then the reference machines' parts, then demand.
8. **Finished:** negotiates features, handles every feature it accepts, relies only on what its specification
   guarantees, recovers from errors, timeouts and resets with nothing leaked, holds no authority beyond its device,
   meets item 6 and reports its state to the owner. A driver verified only on emulated devices says which.

## 16. System management

Nothing mutates shared global state, so nothing can break something else.

- **Base system:** one read-only, signed, verified image, updated as a whole into the inactive slot and rolled back
  automatically if it does not boot healthy.
- **Packages:** everything else is an immutable, content-addressed, signed bundle with a manifest of what it
  provides and which capabilities it requests; no install scripts; versions coexist; each carries its own libraries
  and a machine-readable component list.
- **Drivers as packages** bind by device identifiers and update independently; a driver that crashes repeatedly is
  rolled back.
- **Services** are declared in manifests (provides, needs with scopes, restart, placement `cpu=`); the service
  manager routes capabilities; nothing starts by script.
- **One description of the machine** (versions, packages, settings, users), applied transactionally, every change a
  bootable generation; identical documents on identical hardware give identical systems.
- **Apps** see only their own storage plus what the user grants; grants are visible and revocable in one place.
- **Builds** are reproducible (`tools/repro.sh`); packages are signed and logged publicly; repositories are static
  files.

## 17. Project and community

Protocols evolve additively from the first `stable` release, each change with a reason. Every change passes the same
gates. A driver kit (class frameworks, mock-device rig, template, guide) lets vendors ship driver packages. The
supported-hardware list is short and exact. Reference documentation is generated from the source and fails the build
when out of date.

## 18. How components connect

Each seam is decided before the code on either side and written into its protocol: **discovery** (how each side finds
the other, and what the owner sees when it cannot), **authority** (which capabilities cross, who grants and revokes
them; the least that does the job), **lifecycle** (start, readiness, restart, upgrade, removal, and what the other
side sees during each), **failure** (what each error means, who recovers, what survives), **versioning** (how older
and newer sides keep working), and **cost** (copies, round trips and wake-ups per operation, measured). One mechanism
serves each across the system, so a driver, a service and an application are declared, started, granted, observed
and updated alike.

A seam is judged by the people outside it: the driver author with a device, its datasheet and a weekend; the
application author with only the published bindings; the owner, who inspects, scripts and swaps any component; the
end user, who plugs in, installs or updates and it works; and the company, which describes machines in one document,
applies policy and relies on interfaces for years. The safe path is the shortest path for an author, or it is skipped.
