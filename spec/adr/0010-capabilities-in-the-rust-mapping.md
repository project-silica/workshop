# ADR 0010: How moved capabilities appear in generated Rust

Status: accepted. Made while implementing A06.04 (ADR 0001, mode `escalations`). Refines
`spec/adr/0004-generated-rust-mapping.md` as amended by `spec/adr/0009-idl-transport-before-libsys.md`.

## Context

ADR 0009 makes capabilities move: `Capability` is not `Clone`, `Transport::call` takes the request capabilities by
value, and generated decoding checks object types. ADR 0004's shapes clone in three places: the encoder pushed a
clone of each capability into the list (`encode(&self)`), the decoder cloned each one out of a borrowed list, and
a decoded `array<T>` re-decodes its elements on every iteration. Without `Clone`, each of these needs another
shape. Nothing outside `idl` uses the bindings yet.

## Decision

1. **Encoding takes values by value.** `Encode` keeps `encode(&self, e)`, which writes the bytes and, for a
   capability, only its index. A second method `move_caps(self, caps)` then moves the capabilities into the
   `CapList` in the same order (default: none). Generated `encode_message(self, buf, caps)`,
   `encode_request(.., params)` and `encode_reply(.., results)` take the value by value. If encoding fails, the
   value and its capabilities are dropped and the list is empty.
2. **Decoding takes the capability list by value.** Generated `decode_message(msg, caps: CapList<C>)`,
   `decode_request` and `decode_reply` consume the list, move each referenced capability out, and drop (release)
   the rest with the list. `Decoder` has a second lifetime for the list: `Decoder<'a, 'c, C>`; the `Decode`
   trait takes `&mut Decoder<'a, '_, C>`.
3. **Object type check.** For a field of type `cap<T>`, `endpoint<P>`, or an `option` of one, generated decoding
   calls `Decoder::cap(Some(name))` with name `T` or `Endpoint`; plain `cap` passes `None`. A capability whose
   `object_type()` is `Some(other)` is `DecodeError::CapType`, which `dispatch` answers with `malformed_request`
   and the client reports as `malformed_reply`. `Capability::object_type` defaults to `None`.
4. **No capability inside an `array` in generated Rust.** `silica_idlc::rustgen` rejects an `array<T>` whose `T`
   can carry a capability (`cap`, `cap<T>`, `endpoint<P>`, or an `option` or struct containing one, at any
   depth). An array is a borrowed slice when sent and a view of the bytes when received, so it cannot own moved
   capabilities, and with at most four capabilities per message such an array is never needed: use up to four
   `option<cap<T>>` fields. The language (section 2) and `silica-idlc check` still accept such a type; only
   generation refuses it. Arrays decode their elements through a decoder without capabilities, so an element that
   claims one is malformed.
5. **Generated derives.** A struct that has the parameter `C` only through arrays carries no capability; it gets
   hand-written `Clone`, `PartialEq` and `Debug` that do not require them of `C`. A struct that carries a
   capability keeps the derives, which require them of `C`.
6. **`dispatch(server, request, caps: CapList<C>, reply, reply_caps) -> usize`.** It takes the request
   capabilities by value and always produces a reply: `unknown_method`, `malformed_request`, or, when the
   server's reply does not fit, `reply_too_large` after releasing the reply's capabilities
   (`silica_idl_rt::status_reply`). A `reply` buffer shorter than the 16-byte header gets length 0, which the
   caller sees as `malformed_reply`.
7. **ClientCore** keeps no capability lists between calls; it builds the request list per call and moves it into
   `Transport::call`.

## Consequences

- A host test that reuses a capability list across several decodes clones it first (`cl.clone()` with a
  `Clone` stand-in). The A06.02 tests were migrated that way; no assertion changed. Two changes in
  `idlc/tests/round_trip.rs` follow from ADR 0009: the "unknown status" check now uses status 5 (status 4 is
  defined), and the old status-4 case stays as "status 4 with a payload is malformed".
- `idlc/tests/transport.rs` uses a capability stand-in that is not `Clone` and counts live instances; it shows no
  capability is duplicated, lost, or kept after a failed call, a too-large request, or a too-large reply.
- Unknown: whether libsys wants to decode in place without consuming the list (for example to retry a decode).
  Nothing needs it today.

## How to reverse

Before M2: lift rule 4 by giving arrays an owned representation for capability elements (at most four), and
change the other shapes back by regenerating. After M2 every point is a breaking change of the generated API and
goes through `spec/REPOSITORIES.md` section 2 rule 3.
