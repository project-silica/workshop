# Build and release

## 2. Hosted CI

The shared workflows in `.github` run the same compiler, tests and QEMU runner as a workstation, from a fresh clone
and an empty evidence store, in a toolchain image built from `os/tools/image/Containerfile`: the fast tier on every
push, the deep tier nightly.

## 7. Versions

| Thing | Version scheme | Why |
| --- | --- | --- |
| Platform API (`idl` + `libsys`) | **API level**, one increasing integer | Apps and drivers declare the minimum they need; additive evolution means higher levels run older software. |
| The OS (`os` manifest) | `YYYY.MM.patch` | A snapshot of pins, not a library. |
| Component repos | Commits, no versions or tags | The manifest is the only place versions meet. |
| SDK crates | Semantic versions tied to the API level | External developers need ordinary dependency resolution. |
| Packages and drivers | Their authors' versions | Released independently of the OS. |

## 8. Release channels

A release promotes an image already built and tested; nothing is rebuilt.

| Channel | Source | Cadence | Gate |
| --- | --- | --- | --- |
| `nightly` | Latest `os/main` that passed nightly | Daily | Nightly run green |
| `beta` | A chosen nightly | Weekly | 72-hour soak clean, `main` green, no performance regression |
| `stable` | A beta | Every 6 weeks | 2 weeks in beta with no blocker; upgrade and rollback tested from the previous stable |

Promotion creates `release/<version>` on `os`, signs the images, publishes the component list and reproduction
instructions, and records the release in the public log. Fixes land on `main` first and are cherry-picked as pin
moves; security fixes skip the beta wait.

## 9. When not to release

- Nothing before M4 (nightly images from M1 are development builds); no `beta` before M6; no `stable` before the M9
  exit test.
- No first `stable` before the outside-developer trial: someone who did not work on the project uses the published
  SDK and documentation for their own task, and every undocumented step, request for broader authority or need for
  help becomes a protocol or documentation change.
- No tags or release notes on component repos; no release for what a package update can fix; no release on a red
  nightly.
