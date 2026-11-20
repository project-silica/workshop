# ADR 0002: IDL grammar, wire format and evolution rules

Status: accepted. Answers escalation INIT-2. The full rules are in `spec/IDL.md`.

## Context

A06.01 and A06.02 need a grammar and a wire format. Both cross a boundary: every protocol, every generated binding
and every provider and consumer depends on them. The spec only said that protocols are versioned and evolve
additively (`spec/ARCHITECTURE.md` section 4, `spec/REPOSITORIES.md` section 2 rule 3) and that IPC is synchronous
call/reply on Endpoints with capabilities and Frames transferred in the message (`spec/ARCHITECTURE.md` section 6).
The sample `idl/protocols/sample/echo.idl` used a provisional syntax with no ordinals or errors.

## Decision

- Grammar: one `protocol <dotted.Name> version <n>` per file, call/reply methods only, each with an explicit
  ordinal (`name @n (params) -> (results) error E;`), structs, enums with an explicit width and values, types
  `u8..u64`, `i8..i64`, `bool`, `string`, `bytes`, `array<T>`, `option<T>`, `cap`, `cap<ObjectType>`,
  `endpoint<Protocol>`, and `reserved @n;` for retired ordinals.
- Wire format: a 16-byte little-endian header (ordinal, flags, status, sender version, payload length), then the
  payload as length-prefixed field lists in declaration order, no padding; capabilities only out of band as
  indices into the kernel message's capability list; at most 4096 bytes and 4 capabilities per message.
- Evolution: append-only fields with defaults, new methods, new variants; decoders skip unknown trailing fields,
  default missing trailing ones, map unknown enum values to `Unknown(raw)`, and servers answer unknown ordinals
  with `unknown_method`.
- A uniform transport contract for revocation, provider restart and cancellation (`spec/IDL.md` section 5).

This differs from the initializer's recommendation in three places: explicit ordinals (positional ordinals break
on the pre-stable removals that `spec/ARCHITECTURE.md` section 4 allows); length-prefixed field lists without
alignment instead of inline/out-of-line with offsets (fewer cases to validate, smaller decoder, and trailing fields
can be skipped at any nesting level); and a 4 KiB message limit instead of 64 KiB.

## Consequences

- Decoding is a single forward pass with no allocation and no offsets to chase, which keeps it small and easy to
  fuzz (`spec/TESTING.md`: fuzz every server's decoder).
- Fields are read sequentially, so a field cannot be read without decoding the ones before it. Messages are at
  most 4 KiB, so this costs little.
- The 4 KiB and 4-capability limits bound what the kernel must copy per call (C09); bulk data goes through Frames
  and rings, as `spec/ARCHITECTURE.md` section 6 already requires. The kernel's actual message registers and IPC
  buffer are decided in C09 and need only carry these limits.
- Version skew between an older and a newer peer is tolerated in both directions without negotiation.

## What is still unknown

- Whether 4096 bytes and 4 capabilities fit the M3 protocols (block, file, config). Raising either is additive.
- How generated bindings reach other repositories; decided in mode `plan` before M2.
- Whether the C bindings (I03) want alignment; if so they copy out of the decoded view, the wire stays as is.

## How to reverse

Before the first `stable` release the wire format can be replaced: add a new header flag bit for the new format,
teach `silica-idl-rt` both, move every provider and consumer, then drop the old one (`spec/REPOSITORIES.md`
section 2 rule 3). Grammar changes only need the compiler and the `.idl` files updated, both in `idl`.
