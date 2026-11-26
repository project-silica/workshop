# Repositories

Public repositories live in the [Project Silica organization](https://github.com/project-silica), split along stable
interface boundaries.

| Repo | Contains |
| --- | --- |
| `.github` | Organization profile and the reusable CI workflows |
| `idl` | Every interface definition, the IDL compiler and runtime: the platform's stable contract |
| `kernel` | `kernel-core`, `kernel`, arch directories, `libsys`, the UEFI loader, kernel tests and proofs |
| `os` | Integration: `manifest.toml` pinning every repository, image builder, QEMU runner, system tests, benchmarks, `tools/` |
| `workshop` | `AGENTS.md`, `spec/`, the workspace bootstrap and the pinned revisions (`bootstrap.pins`) |
| `system` | The runtime, process spawner, service manager, device manager, drivers, storage, network, logging, shell, remote management |

Planned, each created at its milestone and only once its boundary is stable: `drivers` and `storage` (M3; until then
in `system/drivers/` and `system/storage/`, where a framework change and its users are one commit), `network` (M4),
`sdk` (M5), `graphics` and `desktop` (M6), `packages` (M7), `docs` (M4). Third-party drivers and apps live in their
authors' repositories and ship as packages.

## Dependencies

Applications and services use the public IDL and libsys interfaces. A repository names another's crates by path, as
its sibling in the workshop: the workshop layout is the build layout. The kernel imports no service implementation.
`os` may use any repository's crates (its host tools speak the system's protocols with the system's own crates).
Nothing depends on `os` or the workshop. `tools/check-deps.sh` enforces this.
