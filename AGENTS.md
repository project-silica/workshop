# Silica

Silica is one operating system for desktops and servers, with or without a GUI: a capability microkernel in Rust,
drivers and services in userspace. You own its design and its code: decide, build, measure, land it on `main`, and
report what you did.

What it must be, in order of what wins a conflict:

1. **Secure and stable**: nothing less trusted can crash, starve or deceive something more trusted, and committed
   data is never lost or silently corrupted.
2. **Small, and derived from its own model**: every mechanism follows from what authority a capability carries, who
   holds it, and what the kernel can report. Each has a present reason, and a new need is met with a mechanism that
   exists before a new one.
3. **Fast**: as fast as the hardware allows. Each path is tuned against Silica's own best until a profile shows
   that what remains is work the hardware or a guarantee requires. Linux's numbers in `os/bench/reference.tsv` are a
   floor to stay above.
4. **Buildable from its docs**: a driver or an app can be written from the published interfaces alone.

Silica carries none of Unix's history, so it can reach results Linux cannot. Be inventive about design and
uncompromising about correctness.

## How Silica solves a problem

Robustness is required, and it is a guarantee, not a mechanism. Say first what must never happen (a hung driver
holds no client; one program cannot fill what others need; the machine recovers unattended), then carry that
guarantee with what Silica has. A conventional system would reach for a timeout, a retry, a grace period, a quota, a
rate limit, a setting or a privileged supervisor. Each of those stands in for something Silica's kernel knows or a
capability already scopes, so when one comes to mind, find what it stands in for. The moves, in the order to try:

1. **Remove the cause.** A defect exists because something is shared, ambient or guessed. Taking that out beats
   adding a guard beside it, and the system gets smaller.
2. **To learn a fact about another party, get it from the kernel**: that it ended, faulted, owes an answer, took
   its notification, still holds a capability (exit and fault messages, `CapNotice`, notifications, parked calls,
   `Inspect`). When the kernel cannot report the fact yet, the work is making it report it.
3. **To limit what a party consumes, make it the party's own**: objects from its Untyped, state in memory it
   lent, processor time from its scheduling context. What a holder pays for needs no table and no quota, and comes
   back when its capability goes.
4. **To grant authority or configuration, give it to the one component it concerns**, as a capability or a field
   of its declaration, checked with the image it ships in. The boot string holds the kernel's own settings and
   nothing a service reads.
5. **To test a failure, build the thing that fails**: a hostile program or device model in the test image, or code
   under the `harness` Cargo feature, which only test images build. The server image is checked to contain none.
6. **Time judges only what no kernel can speak for**: a device (the bound from its specification) and a host on
   the network (budgeted per peer). Inside the machine a time bound is a backstop behind a kernel-reported fact;
   when the normal path or a passing test waits for it, the design is unfinished.

A commit that adds a mechanism (a syscall, an object field, a protocol method, a table, a time bound, a service, a
setting) says which guarantee it carries, which move it is, and which existing mechanism was tried first. One that
resembles a Unix or Linux mechanism also says why the moves above do not serve. `tools/size.sh` holds the ceilings
(kernel lines, syscalls, object types); a change that needs one raised says why beside the number. The
`server_image` test boots a production image with every test hook's words on its command line and fails if any is
obeyed or present: a package that gains a hook adds its words there.

## Invariants

These hold at every trust boundary (a syscall, a protocol method, a parser of untrusted bytes, a device's answer).

- **Least authority, carried by the capability.** A holder can do what its capability's rights and scope say and
  nothing more; a new method says which scope it needs.
- **A holder pays for what it consumes, and it comes back when the holder goes** (move 3). Where a service must
  keep state for a client in its own memory, the bound is the client's, stated in its declaration.
- **Knowledge comes from the kernel, not the clock** (moves 2 and 6). Nothing waits forever on something it trusts
  less: the wait ends on the kernel's report, with a bound behind it whose expiry is that peer's failure.
- **Authority and configuration arrive as capabilities** (move 4): not a string every component reads, a
  well-known number anyone may claim, or a switch a production image obeys.
- **Less-trusted input changes what a more-trusted part believes only after being checked**: time, routes,
  neighbours, leases, versions, device state.
- **The first holder keeps what it holds.** A second claimant is refused, not put in its place.
- **Untrusted bytes are decoded totally and shown inertly**: no panic on any input, no control character reaches a
  terminal.
- **Fail closed and say why.** An unknown field, an unsupported feature, an unconfined device is refused by name.
- **Secrets live only where they are needed** and are wiped after use.
- **A cost an attacker can trigger is a security bug**, not a performance limit to measure later.
- **A guarantee beats a number.** When safety costs speed, record the cost and its reason in `os/bench/open.tsv`,
  then win it back in the design.

## Done

- A change at a trust boundary comes with a test that mounts the attack and fails on the code before it. Write the
  test first, run it on the unchanged code, and put that failure in the commit message.
- Tests check correctness; they do not define it. A test, fuzz floor, budget, gate or margin is not loosened to
  pass: a change that removes fuzz coverage brings coverage of its own code to make it up.
- Run a change's own tests while you work, in one invocation (`--guest A --guest B`); `--fast` before a commit
  reaches `main`; `--full` before a pin. A new check joins a guest boot that already has the devices and services
  it needs before it gets a boot of its own.
- A benchmark answers a question you state first. Instruction counts (`bench.sh --only insns`) are exact and
  disturb nobody: use them first on any kernel path. Timed runs take over the machine: not while someone is at
  its desktop. A performance change is finished when its profile shows no removable cost left; its commit records
  the profile and what was tried.
- A driver that only works in QEMU is a prototype; what needs real hardware is recorded as owed, with its test.

## Landing

Work is finished when it is on `main` of every repository it touched, pushed, and `tools/landed.sh --remote` prints
`LANDED`. It prints one line for each branch, worktree, unpushed commit, modified file and open pull request.

1. One branch per piece of work, with the same name in each repository it touches. Push it with its first commit
   and open its pull requests then (`gh pr create`), so the work is visible while it is in progress.
2. Merge when `check / pre-merge` is green: `idl`, `kernel` and `system` first, then `tools/pin.sh` and the `os`
   pull request, then the workshop's. CI builds a pull request against the same-named branch of the other
   repositories where one exists.
3. Delete the branch (local and remote) and its worktree as it merges. A checkout made to run a test on older
   code, or to compare designs, is removed in the session that made it.
4. Start a session with `tools/landed.sh`. What it lists is the first work: land it, or delete it and say why. A
   branch that must outlive a session is named in `spec/MILESTONES.md` with what it waits for.

## Commands

From the workshop root: `./bootstrap.sh` (fetch the pinned repositories), `./tools/init.sh` (check the toolchain),
`./tools/test.sh --fast | --full | --deep`, `./tools/test.sh --guest NAME` (one guest test), `cargo test -p <crate>
<name>`, `./tools/bench.sh --only insns --compare A,B`, `./tools/fuzz.sh --target NAME`, `./tools/size.sh`,
`./tools/boot.sh [--system]`, `./tools/pin.sh` (record component commits in `os/manifest.toml` and `bootstrap.pins`),
`./tools/landed.sh [--remote]`. Results land in `target/logs/`.

## The record

Each session starts without memory. The state is in: the commit messages (what was built, what a user can now do,
and a last line `Ran: ...`), the current milestone's open list in `spec/MILESTONES.md`, the measured gaps in
`os/bench/open.tsv`, and what `tools/landed.sh` prints. Change the milestone list in the commit that closes or
finds an item. Add no other tracking files.

## Layout and gotchas

- `idl`, `kernel`, `system`, `os` and `.github` are separate Git repositories inside the workshop; `tools` links
  to `os/tools`. Commit in the repository that owns the change. `MILESTONE` holds the last milestone declared
  (raised when its exit test passes); the tools require that milestone's budgets and gates.
- The spec (`spec/`) holds decisions and promises only; history and measurements belong in commit messages.
  Change the spec in the same work as the code, on evidence.
- `unsafe` only in the modules `spec/UNSAFE_MODULES.md` lists, each use with its invariant stated.
- No Python anywhere: host programs a test needs are Rust in `os/host-tools`.
- Edit files with the Edit and Write tools; a script only for one mechanical change across many files.
- `/tmp` is 8 GB of RAM: put scratch, logs and checkouts under `target/`.
- Each checkout needs its own `CARGO_TARGET_DIR`: a shared one serves one tree's build to the other.
