# ADR 0008: Known-answer vectors for the IDL wire format

Status: accepted. Answers M0 gate blocker B2 (`state/gates/M0.md`, feature A06.02).

## Context

`spec/IDL.md` section 3 fixes the wire format in prose only. Every test of A06.02 and A06.03 encodes with
`silica-idl-rt` and decodes with it again.

Observation: at the M0 gate the evaluator made integers big-endian on both encode and decode
(`idl/rt/src/codec.rs:326,331`). `VERIFY: PASS` still held for A06.02 and A06.03, and two independent plants
confirmed it. A symmetric error is invisible to round-trip tests. A second implementation (libsys at M2, C bindings
later) would have nothing to agree with.

## Decision

1. `spec/IDL.md` section 3.1 lists seven normative byte vectors for `sample.Echo`. They cover the header, both
   flag values, statuses `ok`, `error` and `unknown_method`, every integer width, signed values, `bool`, enums,
   `string`, `bytes`, nested field lists, `array`, both `option` states and capability indices. They were written
   from the prose of section 3 by an independent script (Python `struct`, little-endian), not by `silica-idl-rt`.
2. A06.02 gets a named test, `idlc/tests/wire_vectors.rs::known_answer_vectors`. It encodes each value with the
   generated code and compares the bytes with section 3.1. It also decodes each vector, with the stated
   capability count, and compares the values. The vectors are copied into the test from the spec text. They are
   never regenerated from the encoder.
3. Where the code and section 3.1 disagree, the code is wrong. A real error in a vector is corrected only by an
   ADR that names it.

## Consequences

- The big-endian plant, and any other symmetric layout error, now fails A06.02.
- libsys and every later binding reuse the same seven vectors as their first conformance test.
- Unknown: section 3.1 does not cover `malformed_request` replies or every limit. Those stay with the rejection
  tests of A06.02.

## How to reverse

Delete section 3.1 and the named test. Round-trip tests alone then guard the layout again.
