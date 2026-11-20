# ADR 0005: Exact rules of the evolution check; no capability in an appended field

Status: accepted. Made while implementing A06.03 (ADR 0001, mode `escalations`).

## Context

`spec/IDL.md` section 4 lists the additive changes and says `silica-idlc check-compat <old> <new>` enforces them.
Implementing the check exposed one contradiction and three gaps.

Contradiction: section 4 allows appending a capability field inside `option` ("so a capability is appended only
inside `option`"). Section 3 says capability indices appear in encoding order 0, 1, 2, ... and every transferred
capability is referenced exactly once, otherwise the message is malformed. An older decoder skips the bytes of a
field it does not know, but cannot release or account for the capability those bytes index. So when a newer peer
sends a present appended `option<cap>` (or a non-empty appended `array<cap>`, or a struct holding one), the older
peer finds an unreferenced capability, or a later known capability out of order, and rejects the whole message as
malformed. The observation is reproducible by reading `rt/src/codec.rs` (`Decoder::end_list` skips bytes;
`Decoder::finish` returns `UnusedCap`). The appended capability would break exactly the skew section 4 promises to
tolerate.

Gaps: whether new items and enum variants may be inserted between old ones; what "each additive change increments
`version`" means for doc-only edits and for comparisons across several versions; the command's exact shape.

## Decision

1. An appended field (parameter, result or struct field) may not have a type that can carry a capability at any
   depth: not `cap`, `cap<T>`, `endpoint<P>`, nor `option`, `array` or a struct containing one. A new capability
   travels in a new method. Fields that existed in version 1 of a message may carry capabilities as before.
2. Old items (methods, structs, enums, `reserved` ordinals) and old enum variants keep their relative order; new
   items and new variants may be inserted anywhere. Fields are only appended, as section 4 already says. An item
   keeps its kind (a struct does not become an enum).
3. `version` never decreases. It increases, by any amount, when anything other than doc comments changed; a
   doc-only change may keep it.
4. `silica-idlc check-compat <old.idl> <new.idl>` parses each file on its own (rules of section 2 that need one
   file), then compares. It prints one `ERROR: <file>:<line>:<col>: <message>` per violation (a removal points at
   the old file, everything else at the new file) and exits 1 on any, 0 when compatible, 2 on a usage error.
   Rules that need other files (`endpoint<P>` resolution) stay with `silica-idlc check`.

## Consequences

- Section 4 no longer promises something the wire format cannot deliver; `check-compat` and the runtime agree.
- A protocol that needs to hand over a new capability adds a method instead of a field. Methods are cheap
  (ordinals are 32 bits) and old providers answer `unknown_method`, which callers already handle.
- The runtime decoder stays strict (canonical encoding, every capability accounted for).
- Tests: `idl/idlc/tests/versioning.rs::additive_only` (every rule, accepted and rejected) and `::version_skew`
  (generated v1 and v2 clients and servers of `idlc/tests/versions/*/skew/counter.idl` against each other).

## How to reverse

Rule 1 can be loosened later without breaking any protocol, because it only forbids. To allow appended
capabilities, change section 3 so a decoder that skipped unknown bytes accepts gaps in increasing capability
indices and unreferenced capabilities, and releases every capability it did not decode; then drop the
`carries_cap` rule in `idl/idlc/src/compat.rs`. Still unknown: whether any protocol before M5 needs it. Rules 2 and
3 can likewise be loosened; tightening any of them later would need every existing protocol rechecked.
