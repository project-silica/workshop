# Silica

Silica is one operating system for desktops and servers, with or without a GUI: a capability microkernel in Rust,
drivers and services in userspace. You own its design and its code; decide, build, measure, and report what you did.

What it must be, in order of what wins a conflict:

1. **Secure and stable**: nothing less trusted can crash, starve or deceive something more trusted, and committed
   data is never lost or silently corrupted.
2. **Small, with no inherited abstraction**: no `fork`, `ioctl`, signals, TTYs, uid 0, global namespace or ring-0
   drivers. Each mechanism has a present reason, and a new need is met with a mechanism that exists before a new one.
3. **Fast**: as fast as the hardware allows. Each path is tuned against Silica's own best until a profile shows
   that what remains is work the hardware or a guarantee requires; every improvement becomes the new ratchet.
   Linux's numbers in `os/bench/reference.tsv` are a floor to stay above, not a finish line.
4. **Buildable from its docs**: a driver or an app can be written from the published interfaces alone.

## Invariants

These hold at every trust boundary (a syscall, a protocol method, a parser of untrusted bytes, a device's answer).
Each is why a class of the 2026-11-24 audit's defects existed; designing to them is cheaper than finding them later.

- **Least authority, carried by the capability.** A holder can do what its capability's rights and scope say and
  nothing more; a new method says which scope it needs. (Every holder could once replace any service's program.)
- **Everything a less-trusted party can consume is bounded per holder and given back when the holder goes**: slots,
  connections, windows, queue entries, memory, processor time, time holding locks. (Tables filled by one client.)
- **Nothing waits forever on something it trusts less.** Calls into drivers and peers have time limits; a peer that
  ends is noticed. (A hung driver held its service and every client of it.)
- **Less-trusted input never changes what a more-trusted part believes without being checked**: time, routes,
  neighbours, leases, versions. (One forged packet redirected traffic for the router.)
- **The first holder keeps what it holds.** A second claimant is refused, never silently put in its place.
- **Untrusted bytes are decoded totally and shown inertly**: no panic on any input, no control character reaches a
  terminal.
- **Fail closed and say why.** An unknown field, an unsupported feature, an unconfined device is refused by name,
  never ignored.
- **Secrets live only where they are needed** and are wiped after use.
- **A cost an attacker can trigger is a security bug**, not a performance limit to measure later.
- **A guarantee beats a number.** When safety costs speed, record the cost and its reason in `os/bench/open.tsv`,
  then win it back in the design.

## Done

- A change at a trust boundary comes with a test that mounts the attack and fails on the code before it. Run it
  against the old code and put that failure in the commit message.
- Tests check correctness; they do not define it. Never loosen a test, fuzz floor, budget, gate or margin to pass:
  a change that removes fuzz coverage brings coverage of its own code to make it up.
- Every change runs its own test while you work, `--fast` before a commit, `--full` before a pin.
- A benchmark answers a question you state first. Instruction counts (`bench.sh --only insns`) are exact and
  disturb nobody: use them first on any kernel path. Timed runs take over the machine: not while someone is at
  its desktop. A performance change is finished when its profile shows no removable cost left, not when a target
  is met; its commit records the profile and what was tried.
- A driver that only works in QEMU is a prototype; what needs real hardware is recorded as owed, with its test.

## Commands

From the workshop root: `./bootstrap.sh` (fetch the pinned repositories), `./tools/init.sh` (check the toolchain),
`./tools/test.sh --fast | --full | --deep`, `./tools/test.sh --guest NAME` (one guest test), `cargo test -p <crate>
<name>`, `./tools/bench.sh --only insns --compare A,B`, `./tools/fuzz.sh --target NAME`, `./tools/size.sh`,
`./tools/boot.sh [--system]`, `./tools/pin.sh` (record component commits in `os/manifest.toml` and `bootstrap.pins`).
Results land in `target/logs/`.

## The record

Each session starts without memory. The state is in: the commit messages (what was built, what a user can now do,
and a last line `Ran: ...`), the current milestone's open list in `spec/MILESTONES.md`, and the measured gaps in
`os/bench/open.tsv`. Work not yet on `main` is on a pushed branch that the milestone list names. Change the list
in the commit that closes or finds an item. Add no other tracking files.

## Layout and gotchas

- `idl`, `kernel`, `system` and `os` are separate Git repositories inside the workshop; `tools` links to
  `os/tools`. Commit in the repository that owns the change, push components before the workshop, land through a
  pull request to each `main`. `MILESTONE` holds the last milestone declared (raised when its
  exit test passes); the tools require that milestone's budgets and gates.
- The spec (`spec/`) holds decisions and promises only; history and measurements belong in commit messages.
  Change the spec in the same work as the code, on evidence.
- `unsafe` only in the modules `spec/UNSAFE_MODULES.md` lists, each use with its invariant stated.
- No Python anywhere: host programs a test needs are Rust in `os/host-tools`.
- Edit files with the Edit and Write tools; a script only for one mechanical change across many files.
- `/tmp` is 8 GB of RAM: put scratch, logs and checkouts under `target/`.
- Each checkout needs its own `CARGO_TARGET_DIR`: a shared one serves one tree's build to the other.
- Subagents: for independent work in its own worktree, and for a fresh review of any change at a trust
  boundary (give the reviewer the diff and these invariants, not your reasoning; ask it to skip style).
