# Repositories

Silica's public repositories live in the [Project Silica GitHub organization](https://github.com/project-silica).
Repositories follow stable interface boundaries. Each has a distinct audience
or release cadence.

## 1. The repositories

| Repo | Contains | Created at |
| --- | --- | --- |
| [.github](https://github.com/project-silica/.github) | Organization profile and the reusable CI workflows used by every other repo | M0 |
| [idl](https://github.com/project-silica/idl) | Every interface definition, the IDL compiler, generated-binding conformance tests. This is the stable contract of the platform. | M0 |
| [kernel](https://github.com/project-silica/kernel) | `kernel-core`, `kernel`, arch directories, `libsys`, the UEFI loader, kernel tests and proofs | M0 |
| [os](https://github.com/project-silica/os) | The integration repo: `manifest.toml` pinning one commit of every other repo, image builder, QEMU runner, system-level tests, benchmarks, `tools/`, release tooling | M0 |
| [workshop](https://github.com/project-silica/workshop) | The project root: `AGENTS.md`, this specification (`spec/`: architecture, component inventory, milestones, testing strategy, IDL rules and their rationale, glossary), workspace bootstrap and the pinned component revisions | M0 |
| `system` | Core services: root task, service manager, process manager, memory manager, device manager, config store, logging, time, identity, capability broker, update and package services, shell | M2 |
| `drivers` | Driver host, class frameworks, the mock-device rig, every first-party driver, each driver's `BEHAVIOR.md` | M3 |
| `storage` | Block server, namespace server, native filesystem, package blob store, other filesystem readers, encryption | M3 |
| `network` | Network stack, protocol services, TLS, firewall, Wi-Fi supplicant | M4 |
| `sdk` | Compiler target definitions, C/C++ bindings and runtime, language backends, WebAssembly component runtime, templates, debugger and profiler support | M5 |
| `graphics` | Compositor, renderer, font stack, UI toolkit, input stack, audio server | M6 |
| `desktop` | Shell surfaces and the core apps | M6 |
| `packages` | Build recipes for third-party software ported to the platform (Servo and others) | M7 |
| `docs` | Source of the public documentation site; reference pages are generated from `idl` and `spec` | M4 |

The five linked M0 repositories already exist on GitHub with `main` as their default branch. The specification lives in the workshop so it changes alongside the instructions and pins that depend on it. The remaining rows are planned repositories.

Third-party drivers and apps live in their authors' own repositories and are
published as packages. Nothing third-party is merged into these repos.

Do not create a repository before its milestone. An empty repository is noise.

## Dependencies

Applications and services use the public IDL and libsys interfaces. The kernel does not import service implementations. The integration repository builds images and runs system tests against the revisions in its manifest.
