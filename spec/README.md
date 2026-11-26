# Silica specifications

The current design. `AGENTS.md` says how it is used and changed; commit messages hold the history.

- [Architecture](ARCHITECTURE.md): invariants, size budgets, and each component's promises
- [Milestones](MILESTONES.md): exit tests and what the current milestone lacks
- [Testing](TESTING.md): what finished means, what runs when, oracles, gates
- [Components](COMPONENTS.md): the parts the milestones name
- [IDL](IDL.md) and [IDL rationale](IDL_RATIONALE.md): the interface language, wire format and generated Rust
- [Repositories](REPOSITORIES.md), [Build and release](CI_RELEASE.md), [Unsafe modules](UNSAFE_MODULES.md)

Names in code and documents follow the kernel's (`silica_abi`: `Cap`, `Rights`, `ObjectType` and its ten types) and
the IDL's; do not introduce synonyms.
