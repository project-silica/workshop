# IDL rationale

`spec/IDL.md` states the rules of the IDL, its wire format and the generated Rust. This file says why each rule is
the way it is, what it costs, what is still unknown and how to reverse it. It describes the current design. When a
rule changes, change `spec/IDL.md` and rewrite the matching section here, so that this file never becomes a history.

## 1. Grammar and wire format

The compiler (A06) needs a grammar and a wire format, and every protocol, generated binding, provider and consumer
depends on both. The architecture only requires that protocols are versioned and evolve additively
(`spec/ARCHITECTURE.md` section 4) and that IPC is synchronous call/reply on Endpoints with capabilities and Frames
transferred in the message (section 6).

The design:

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

Three choices differ from the more common design. Ordinals are explicit, because positional ordinals break on the
removals that `spec/ARCHITECTURE.md` section 4 allows before the first stable release. Field lists are
length-prefixed without alignment, where the usual layout is inline and out-of-line parts with offsets: there are
fewer cases to validate, the decoder is smaller, and trailing fields can be skipped at any nesting level. The
message limit is 4 KiB where 64 KiB is typical.

Consequences:

- Decoding is a single forward pass with no allocation and no offsets to chase, which keeps it small and easy to
  fuzz (`spec/TESTING.md`: fuzz every server's decoder).
- Fields are read sequentially, so a field cannot be read without decoding the ones before it. Messages are at
  most 4 KiB, so this costs little.
- The 4 KiB and 4-capability limits bound what the kernel must copy per call (C09); bulk data goes through Frames
  and rings, as `spec/ARCHITECTURE.md` section 6 already requires. The kernel's message registers and IPC buffer
  need only carry these limits.
- Version skew between an older and a newer peer is tolerated in both directions without negotiation.

Still unknown:

- Whether 4096 bytes and 4 capabilities fit the M3 protocols (block, file, config). Raising either is additive.
- How generated bindings reach other repositories.
- Whether the C bindings (I03) want alignment; if so they copy out of the decoded view and the wire stays as is.

To reverse: before the first `stable` release the wire format can be replaced by adding a header flag bit for the
new format, teaching `silica-idl-rt` both, moving every provider and consumer, then dropping the old one (the
staged migration of `spec/ARCHITECTURE.md` section 4). Grammar changes only need the compiler and the `.idl` files
updated, both in `idl`.

## 2. The Rust shape of generated code

`spec/IDL.md` section 6 fixes what the generator emits (types, request and reply per method, client, server trait,
`dispatch`) and that it depends only on `silica-idl-rt` and `core`. The Rust names and types are visible to every
repository that consumes bindings (first D03 at M2), so they are fixed here. Sections 5 and 6 below refine the
shapes for capabilities.

1. IDL to Rust: integers and `bool` as themselves; `string` as `&'a str`; `bytes` as `&'a [u8]`; `array<T>` as
   `silica_idl_rt::Array<'a, T, C>` (built from a slice, decoded as a view that re-decodes on iteration);
   `option<T>` as `Option<T>`; `cap`, `cap<T>` and `endpoint<P>` as the capability parameter `C`, bounded by
   `silica_idl_rt::Capability`. A struct or message type takes `'a` and `C` only when a field needs them.
2. Each enum gets a final variant `Unknown(raw)` (`spec/IDL.md` section 4), `from_raw` and `raw`. Enum variant
   names are the IDL names in `CamelCase`.
3. Per method `m`: `MRequest` and `MReply` (CamelCase of `m`) with `ORDINAL`, `encode_message` and
   `decode_message`; a reply decodes to `Result<MReply, CallError<E>>`, `E` the method's error enum or
   `core::convert::Infallible`.
4. `Client<T, C>` wraps `silica_idl_rt::ClientCore` (built with `From<T>`), one method per protocol method taking
   the parameters and returning `Result<MReply, CallError<E>>`; the reply borrows the client's buffer.
   `Server<C>` has one method per protocol method taking the parameters and returning `MReply`, or
   `Result<MReply, E>` when the method declares an error. `dispatch(server, request, caps, reply, reply_caps)`
   answers a request whose header is malformed with `malformed_request` carrying the raw ordinal (0 when absent).
5. One module per protocol, named by the last name segment in `snake_case`, in the file
   `<segments in snake_case joined by _>.rs`, with `NAME` and `VERSION` constants.
6. The generator rejects, with file, line and column: a struct or enum named `C`, `Client`, `S`, `Server` or
   `T`; a struct or enum named like a generated `MRequest` or `MReply`, or two methods generating one name; two
   variants of one enum with the same CamelCase name, or a variant named `unknown`.

Consequences:

- Decoding allocates nothing and generated code needs no `alloc`; a client holds two 4096-byte buffers.
- Rule 6 adds generator-level naming errors on top of `spec/IDL.md` section 2; no existing protocol hits them.
- `tests/round_trip.rs` in `idl/idlc` compiles the generated module of `sample.Echo` and exercises all of it.

To reverse: every point is a generated name or type, so a change regenerates bindings, and before M2 nothing
consumes them. After M2 a change breaks every consumer's source (not the wire format) and follows the staged
migration of `spec/ARCHITECTURE.md` section 4.

## 3. The evolution check, and no capability in an appended field

`spec/IDL.md` section 4 lists the additive changes that `silica-idlc check-compat <old> <new>` enforces.

An appended field cannot carry a capability, because the wire format cannot deliver it to an older peer. Capability
indices appear in encoding order 0, 1, 2, ... and every transferred capability is referenced exactly once,
otherwise the message is malformed (`spec/IDL.md` section 3). An older decoder skips the bytes of a field it does
not know, but it cannot release or account for the capability those bytes index. So when a newer peer sends a
present appended `option<cap>` (or a non-empty appended `array<cap>`, or a struct holding one), the older peer finds
an unreferenced capability, or a later known capability out of order, and rejects the whole message. The behaviour
is visible in `rt/src/codec.rs`: `Decoder::end_list` skips bytes and `Decoder::finish` returns `UnusedCap`. An
appended capability would break exactly the skew that section 4 promises to tolerate.

The rules:

1. An appended field (parameter, result or struct field) may not have a type that can carry a capability at any
   depth: not `cap`, `cap<T>`, `endpoint<P>`, nor `option`, `array` or a struct containing one. A new capability
   travels in a new method. Fields that existed in version 1 of a message may carry capabilities as before.
2. Old items (methods, structs, enums, `reserved` ordinals) and old enum variants keep their relative order; new
   items and new variants may be inserted anywhere. Fields are only appended. An item keeps its kind (a struct
   does not become an enum).
3. `version` never decreases. It increases, by any amount, when anything other than doc comments changed; a
   doc-only change may keep it.
4. `silica-idlc check-compat <old.idl> <new.idl>` parses each file on its own (the rules of section 2 that need
   one file), then compares. It prints one `ERROR: <file>:<line>:<col>: <message>` per violation (a removal points
   at the old file, everything else at the new file) and exits 1 on any, 0 when compatible, 2 on a usage error.
   Rules that need other files (`endpoint<P>` resolution) stay with `silica-idlc check`.

Consequences:

- `check-compat` and the runtime agree, and section 4 promises nothing the wire format cannot deliver.
- A protocol that needs to hand over a new capability adds a method. Methods are cheap (ordinals are 32 bits) and
  old providers answer `unknown_method`, which callers already handle.
- The runtime decoder stays strict (canonical encoding, every capability accounted for).
- Tests: `idl/idlc/tests/versioning.rs::additive_only` (every rule, accepted and rejected) and `::version_skew`
  (generated v1 and v2 clients and servers of `idlc/tests/versions/*/skew/counter.idl` against each other).

To reverse: rule 1 can be loosened later without breaking any protocol, because it only forbids. To allow appended
capabilities, change `spec/IDL.md` section 3 so a decoder that skipped unknown bytes accepts gaps in increasing
capability indices and unreferenced capabilities, and releases every capability it did not decode; then drop the
`carries_cap` rule in `idl/idlc/src/compat.rs`. Whether any protocol before M5 needs it is unknown. Rules 2 and 3
can likewise be loosened; tightening any of them later would need every existing protocol rechecked.

## 4. Known-answer vectors for the wire format

Prose alone does not pin a wire format when every test encodes with `silica-idl-rt` and decodes with it again.
Making integers big-endian on both encode and decode (`idl/rt/src/codec.rs`) left every round-trip test passing: a
symmetric error is invisible to them. A second implementation (libsys at M2, C bindings later) would have had
nothing to agree with.

1. `spec/IDL.md` section 3.1 lists normative byte vectors for `sample.Echo`. They cover the header, both flag
   values, statuses `ok`, `error` and `unknown_method`, every integer width, signed values, `bool`, enums,
   `string`, `bytes`, nested field lists, `array`, both `option` states and capability indices. They were written
   from the prose of section 3 by an independent encoder (little-endian, from the prose alone), never by
   `silica-idl-rt`.
2. `idlc/tests/wire_vectors.rs::known_answer_vectors` encodes each value with the generated code and compares the
   bytes with section 3.1. It also decodes each vector, with the stated capability count, and compares the values.
   The vectors are copied into the test from the spec text and are never regenerated from the encoder.
3. Where the code and section 3.1 disagree, the code is wrong. If a vector itself is wrong, correct it in
   `spec/IDL.md` first, in a commit that names the vector and shows the error from the prose of section 3, and
   change the test to match afterwards.

Consequences:

- A symmetric layout error now fails the vector test.
- libsys and every later binding reuse the same vectors as their first conformance test.
- Section 3.1 does not cover `malformed_request` replies or every limit. Those stay with the rejection tests in
  `idlc/tests/round_trip.rs`.

To reverse: delete section 3.1 and the test. Round-trip tests alone then guard the layout again.

## 5. Capability types, ownership and oversized replies in the transport

An echo client and server written from the documentation and the generated bindings alone worked, but needed three
workarounds, each traced to the shapes of section 2:

1. `cap`, `cap<T>` and `endpoint<P>` all become the one parameter `C`, so no expected object type reaches the code
   that holds a received capability. `spec/IDL.md` section 3 says the transport checks the object type of a
   `cap<T>` where the kernel reports it, and nothing could.
2. `Transport::call` borrowed `&CapList<C>`, `ClientCore` then cleared the caller's list, and `Capability`
   required `Clone`. Kernel capability transfer (C09) moves capabilities, and a kernel handle cannot be cloned
   for free.
3. Generated `dispatch` returned `Result<usize, EncodeError>`. A server whose reply exceeded the limits made
   `dispatch` fail, the provider had no legal reply to send, and the caller waited until `peer_gone` or
   `cancelled`.

The design that removes them:

1. **Object type check in decoding.** `silica_idl_rt::Capability` has `fn object_type(&self) -> Option<&str>`. It
   returns the kernel object type name the transport learned on receipt (`"Frame"`, `"Endpoint"`, ...), or `None`
   when the kernel did not report one. When generated decoding reads the index of a `cap<T>` and the capability
   reports `Some(t)` with `t != "T"`, the message is malformed. A request is answered with `malformed_request`. A
   reply is reported to the caller as `malformed_reply`. `cap` is never checked. `endpoint<P>` checks only that
   the object is an `Endpoint`, because the protocol is a contract (`spec/IDL.md` section 3). Host stand-ins
   return `None` or a fixed name.
2. **Move semantics.** `Capability` does not require `Clone`. `Transport::call` takes the request capabilities by
   value: `call(&mut self, message: &mut [u8], len: usize, caps: CapList<C>, reply_caps: &mut CapList<C>)`: the
   request is `message[..len]` and the reply is written over `message`, one buffer per client (the request is dead
   once sent). The buffer is the client's, not the thread's IPC buffer: every client of a thread shares that one,
   and a reply's views live past the call, so decoding in place there would let one client's call rewrite
   another's reply. From that call on, the transport owns them: it transfers them, or releases them when the call fails. Generated
   client methods take capability parameters by value. When a request is `too_large` (detected before `call`),
   the client drops the capabilities it was given, and the caller does not get them back. `ClientCore` never
   clears a list the caller still holds.
3. **Oversized reply.** Reply status 4 is `reply_too_large`, with an empty payload. When the server's reply does
   not fit the limits of `spec/IDL.md` section 3, generated `dispatch` releases the reply capabilities and encodes
   this status. `dispatch` returns `usize` and cannot fail, because a header-only reply always fits. The caller
   observes the transport error `reply_too_large`.

Consequences:

- Status 4 is part of the wire format. Adding it was possible only because no consumer existed; after M2 a new
  status would be malformed to older callers.
- The vectors of section 3.1 gained one for a `reply_too_large` reply; the others are unchanged.
- The exact kernel object type names come from the capability design (C09 and the rest of section C). Until it
  exists, the names are the IDL names of the types used in `cap<T>`.

To reverse: before M2, restore the shapes of section 2 and remove status 4. After M2, every point breaks libsys and
every consumer's source, and follows the staged migration of `spec/ARCHITECTURE.md` section 4.

## 6. Moved capabilities in generated Rust

Section 5 makes capabilities move: `Capability` is not `Clone`, `Transport::call` takes the request capabilities by
value, and generated decoding checks object types. The plain shapes of section 2 would clone in three places: the
encoder pushing a clone of each capability into the list, the decoder cloning each one out of a borrowed list, and a
decoded `array<T>` re-decoding its elements on every iteration. Without `Clone`, each needs another shape.

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
   `option<cap<T>>` fields. The language (`spec/IDL.md` section 2) and `silica-idlc check` still accept such a
   type; only generation refuses it. Arrays decode their elements through a decoder without capabilities, so an
   element that claims one is malformed.
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

Consequences:

- A host test that reuses a capability list across several decodes clones it first (`cl.clone()` with a `Clone`
  stand-in). In `idlc/tests/round_trip.rs` the "unknown status" check uses status 5, because status 4 is defined,
  and "status 4 with a payload is malformed" is its own case.
- `idlc/tests/transport.rs` uses a capability stand-in that is not `Clone` and counts live instances; it shows no
  capability is duplicated, lost, or kept after a failed call, a too-large request, or a too-large reply.
- Whether libsys wants to decode in place without consuming the list (for example to retry a decode) is unknown.
  Nothing needs it today.

To reverse: before M2, lift rule 4 by giving arrays an owned representation for capability elements (at most
four), and change the other shapes back by regenerating. After M2 every point breaks the generated API and follows
the staged migration of `spec/ARCHITECTURE.md` section 4.
