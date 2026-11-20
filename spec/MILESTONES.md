# Milestones

Use the exit tests to identify the next missing OS behavior. Demonstrate each
milestone on the integrated code with the tests and measurements that exercise
it.
Engineering can proceed as soon as the technical prerequisites exist.

| M | Name | Components | Exit test |
| --- | --- | --- | --- |
| M0 | Harness | A01-A12 | An empty kernel stub builds for 3 targets; `--fast` runs under 60 s and reports `RESULT:`; IDL compiler round-trips a sample protocol; a deliberately failing test prints one `ERROR:` line. |
| M1 | Boot and kernel core | B01-B03, B06, C01-C05, C08, C12-C14, C23, C26 | Boots under OVMF, prints over serial, runs one userspace thread that makes a syscall and exits; reference-model tests for objects and memory pass. |
| M2 | IPC, SMP, capabilities | C06, C07, C09-C11, C15, C17-C20, C24, D01, D03, D06 (libsys and native runtime), B05 (aarch64) | Two processes exchange 1M IPC round trips on 8 vCPUs with no loss; capability fuzz 10 min clean; Kani proofs pass; aarch64 boots to the same test; IPC and context-switch gates met. |
| M3 | Drivers and services | C16, D02, D04, D07, D08 (logging), D09, D14, D15, E01, E02, E04, E16, E17, F01, F08 | Service manager boots the system from manifests; virtio-blk and virtio-net drivers run in userspace; killing either under load recovers within 1 s. |
| M4 | Network server | G01-G08, G12-G15, D13, D21, D08 (tracing and metrics) | Image boots, gets DHCP, syncs time, serves 10k HTTP requests from the host (64 concurrent connections, response sizes from 1 KB to 1 MB, every body checked against its expected hash, zero errors), accepts a remote management session; interop suite green; boot and idle-memory gates met. **This is the server deliverable.** |
| M5 | Storage, security, updates | F02-F07, F11, F12, B04, B07, D05, D06 (Rust `std` port), D10-D12, D17, D18, D20, D22-D25, E18, I01-I03, J01-J04 | Install to disk, reboot, update A to B, corrupt B, automatic rollback; crash-consistency suite green; Secure Boot chain verified; a WASI app and a C program built against the native C bindings run sandboxed: each reads a file from a directory it was granted, is refused a sibling directory and the network, and gets the documented error when the grant is revoked mid-run. |
| M6 | Desktop | E09 (GOP, virtio-gpu), E06 (HID via QEMU xHCI), E11 (virtio-sound), H01-H10, H13, H14, D19 | Boots to login, logs in, opens terminal + file manager + settings with glass panels at 60 fps in software at 1080p on 4 vCPUs; all screens match goldens; full keyboard navigation; accessibility tree complete. **This is the desktop deliverable.** |
| M7 | App platform | I04-I06, I08, I07, H11 | On-device `cargo build` of a native GUI app; a Python program and a JavaScript program run on the component runtime, each built on the third-party package chosen for its language before M7 work began, and each reading a granted file, waiting on a timer, making an HTTP request, and being refused a directory it was not granted; Servo renders a set of reference pages matching goldens. |
| M8 | Real hardware and GPU | E03, E05, E06 (the rest), E07, E08, E09 (the rest), E10, E11 (the rest), E12-E15, C21, D16, H16, F09, F10, G09-G11, B05 (riscv64) | Boots and passes `tools/test.sh --full` on one named reference laptop and one named reference server; suspend/resume works; Vulkan conformance subset passes on Venus. Requires a human with hardware. |
| M9 | Virtualization and release | C22, I09, I10, J05-J12, H12 | the hypervisor service boots an isolated guest; 72 h soak clean; installer and recovery work; release artifacts signed with SBOM. |

External device, signing and release trials are prerequisites for their respective
exit tests. Track their availability separately while local work continues.
