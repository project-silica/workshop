# Building Silica

Build a small, efficient operating system that someone who loves Linux would choose to use. Preserve what earns that affection: ownership of the machine, inspectable behavior, useful diagnostics, and the ability to write your own tools. Judge a departure from Unix by the job its replacement makes easier. A typed device request earns its place when a driver author can discover its arguments, implement it, and diagnose a failed call.

## Exercise engineering judgment

You own design, implementation, debugging and testing across the component repositories. Make ordinary decisions yourself. When a detail is unspecified, choose a reversible default consistent with the architecture and try it against a real caller. When two choices have lasting consequences, build the smallest experiment that distinguishes them. Put the conclusion beside the interface or in the commit that depends on it. Work directly; one engineer can investigate the hardware, write the driver and test it.

Start from what the checkout actually does. Use the user's requested outcome or the next missing behavior in `spec/MILESTONES.md`. Follow a useful operation all the way through the system. For example, saving a document means typing with real input, writing through the storage service, rebooting and opening the same bytes. A failure along that path tells you what to build next. Run commands and resolve failures yourself. If a physical device or external service is unavailable, exercise what you can locally and identify exactly what still needs that resource.

## Design for the next driver and application

Keep privileged mechanisms small. Put device-specific behavior and policy in userspace. Keep raw syscalls private behind libsys; expose typed, versioned service protocols and explicit capabilities. Keep firmware and network compatibility at the boundaries that need it. Consult `spec/ARCHITECTURE.md` for the design constraints and size budgets.

Write a consumer while designing an interface. For a driver, start with a supported device such as virtio-blk. Make buffer ownership, DMA lifetime, completion and reset explicit. Exercise an outstanding request during device restart. As a second device joins the class, move genuinely shared machinery into the driver library so its author can concentrate on the hardware.

For an application, build a small native client using only the published bindings and examples. A file opener should work with the directory it was granted and give a useful error when that grant is revoked. If the example requires kernel internals, undocumented call ordering or excess privileges, improve the interface before building more clients on it.

## Measure the system people will use

Measure the image you boot. Pick the cost relevant to the change: resident bytes, idle wakeups, copies per packet, or input-to-frame latency. Compare on the same workload and hardware. Preserve isolation, recovery and diagnostics when optimizing. Prefer deleting an unnecessary copy or service round trip to moving more code into the kernel.

From the workshop root, `./bootstrap.sh` obtains the pinned repositories, `./tools/boot.sh` boots x86_64 in QEMU, and `./tools/test.sh --fast` checks the integrated build. Commit in the repository that owns the change. Describe what actually ran and what the user or developer can now do.
