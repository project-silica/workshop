# Glossary

Names in code, tests and documents follow this list. Rust items use the
`CamelCase` or `snake_case` form of the term. Do not introduce synonyms.

| Term | Meaning | In code |
| --- | --- | --- |
| Capability | Unforgeable handle to a kernel object with a rights bitmask | `Cap`, `cap` |
| Rights | Bitmask of operations a capability allows; derive may only remove rights | `Rights` |
| Derive | Copy a capability with equal or fewer rights, recorded in the derivation tree | `derive` |
| Revoke | Destroy every capability derived from one capability | `revoke` |
| Derivation tree | Parent/child record of derived capabilities that revoke walks | `DerivationTree` |
| CapSpace | Per-thread table of capability slots (object type) | `CapSpace` |
| Slot | One entry of a CapSpace | `Slot`, `slot` |
| Object type | One of the ten kernel object types (`spec/ARCHITECTURE.md` section 6) | `ObjectType` |
| Untyped | Physical memory owned by userspace, retyped into objects (object type) | `Untyped` |
| Retype | Create kernel objects inside an Untyped | `retype` |
| Watermark | Next free offset inside an Untyped | `watermark` |
| Thread | Schedulable execution context (object type) | `Thread` |
| AddressSpace | Page-table root and its mappings (object type) | `AddressSpace` |
| Frame | Physical memory of one page size that can be mapped (object type) | `Frame` |
| Endpoint | Rendezvous for synchronous call/reply IPC (object type) | `Endpoint` |
| Notification | Word of signal bits; also carries interrupts and timer expiry (object type) | `Notification` |
| SchedContext | CPU budget and period that a thread runs on (object type) | `SchedContext` |
| Hw | A range of hardware resources that are not memory: x86 I/O ports or interrupt lines (object type) | `Hw` |
| Vcpu | Virtual CPU for the hypervisor service, M9 (object type) | `Vcpu` |
| Call / reply | Synchronous IPC: send and block for the one-shot reply | `call`, `reply` |
| Reply capability | One-shot capability a server uses to answer one call | `ReplyCap` |
| Fast path | IPC path that switches directly to a waiting receiver; lives in `.text.fast*` | `fast_path` |
| Donation | Lending the caller's SchedContext to the server for one call | `donate` |
| Pager | Userspace server that resolves page faults of an AddressSpace | `Pager` |
| Supervisor | Endpoint that receives a thread's faults | `supervisor` |
| Fault message | Typed message describing a thread fault | `FaultMsg` |
| Boot information | Versioned struct the loader hands to the kernel (B02) | `BootInfo` |
| Root task | First userspace process, `init`; owns all initial capabilities | `init` |
| Ring | Shared-memory submission/completion queue on Frames plus Notifications | `Ring` |
| Channel | Message queue with capability transfer, built on rings | `Channel` |
| Stream | Byte stream with end-of-stream, built on rings | `Stream` |
| Protocol | Interface defined in IDL; the stable ABI with `libsys` | `protocol` |
| API level | Single increasing integer naming the platform API (`spec/CI_RELEASE.md` section 7) | `API_LEVEL` |
| Provider | The process that implements a protocol | `provider` |
| Manifest | Typed description of a service, driver or package and the capabilities it needs | `Manifest` |
| Driver host | Supervisor that runs and restarts driver processes | `DriverHost` |
| Class protocol | IDL protocol shared by all drivers of one device class | `class protocol` |
| Volume | Partition-level block device served by the block server | `Volume` |
| Reference model | Simple, obviously correct executable model that tests compare against | `model` |
| Pin | Commit of a repository recorded in `os/manifest.toml` | `pin` |
