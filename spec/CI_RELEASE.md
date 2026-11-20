# Build and release

The shared CI workflow checks the submitted checkout with the same compiler, tests and QEMU runner used locally.

## 7. Versions

| Thing | Version scheme | Why |
| --- | --- | --- |
| Platform API (`idl` + `libsys`) | **API level**, a single increasing integer | Apps and drivers declare the minimum level they need. Additive-only evolution means higher levels run older software. |
| The OS (`os` manifest) | Date-based, `YYYY.MM.patch` | It is a snapshot of pins, not a library. |
| Component repos | No versions, no tags | Identified by commit. The manifest is the only place versions meet. |
| SDK crates published for developers | Semantic versions tied to API level | External developers need normal dependency resolution. |
| Packages and drivers | Their own versions, chosen by their authors | Released independently of the OS. |

## 8. Release channels

A release is a **promotion** of an image that was already built and tested.
Nothing is rebuilt to be released.

| Channel | Source | Cadence | Gate |
| --- | --- | --- | --- |
| `nightly` | Latest `os/main` that passed nightly | Daily | Nightly run green |
| `beta` | A chosen nightly | Weekly | 72-hour soak clean, `main` green, no performance regression |
| `stable` | A beta | Every 6 weeks | 2 weeks in beta with no blocker, upgrade and rollback tested from the previous stable |

Promotion creates `release/<version>` on `os`, signs the images, publishes the
component list and the build-reproduction instructions, and records the
release in the public log. Devices on a channel receive it through the normal
A/B update path.

Fixes to a stable release: land on `main` first, then cherry-pick the pin
moves to `release/<version>`, rebuild, run the full gate, promote as a patch.
Security fixes use the same path with the beta wait waived.

## 9. When not to release

- No release of any kind before M4. From M1 there are nightly images as CI artifacts, labelled as development builds.
- No `beta` channel before M6. No `stable` channel before the M9 exit test passes.
- No first `stable` release before the outside-developer trial has happened: a developer who did not work on the project uses the published SDK and documentation for a task they bring, hits a permission denial, and resolves it from the documentation. The record lists every undocumented step, every request for broader authority, and every time an author had to help. Those findings become protocol changes while protocols are still provisional (`spec/ARCHITECTURE.md` section 4). This needs a human and does not block any milestone gate.
- No tags or release notes on component repos, ever. They cause version sprawl with no user.
- No release to fix something a package update can fix. Drivers and apps ship as packages on their own schedule.
- No release on a red nightly, regardless of the calendar. The cadence slips; the gate does not.
