# IDL rationale

Why `spec/IDL.md`'s rules are what they are, and the shapes of generated Rust that every consumer depends on. When a
rule changes, change `spec/IDL.md` and the matching section here.

## 1. Grammar and wire format

- **Explicit ordinals**, because positional ones break on the removals a staged migration allows before `stable`.
- **Length-prefixed field lists without alignment**: one forward pass, no allocation, no offsets to chase, so the
  decoder is small and easy to fuzz, and trailing fields can be skipped at any depth.
- **4000 bytes and 4 capabilities a message**, because that is what one kernel message carries; bulk data goes in
  Frames and rings. Raising a limit is additive.
- **Skew without negotiation:** a reply's unknown trailing fields are skipped, missing trailing fields take their
  defaults, unknown enum values become `Unknown(raw)`, unknown ordinals get `unknown_method`. A request's unknown
  fields are refused (`unknown_field`), because a provider that ignored them would tell its caller that something it
  asked for (a narrower right, a limit) was done. Encoders leave out trailing default fields, so a newer client that
  uses nothing new sends exactly the old request.
- Replacing the wire format before `stable` takes a header flag for the new format, the runtime speaking both, and a
  staged migration.

## 2. The Rust shape of generated code

Fixed because every consumer's source depends on it (refined for capabilities by sections 5 and 6):

1. Integers and `bool` as themselves; `string` as `&'a str`; `bytes` as `&'a [u8]`; `array<T>` as
   `silica_idl_rt::Array<'a, T, C>` (a slice when built, a view that re-decodes when received); `option<T>` as
   `Option<T>`; `cap`, `cap<T>` and `endpoint<P>` as the capability parameter `C: silica_idl_rt::Capability`. A
   type takes `'a` and `C` only when a field needs them.
2. Each enum gets a final variant `Unknown(raw)`, `from_raw` and `raw`; variants are the IDL names in `CamelCase`.
3. Per method `m`: `MRequest` and `MReply` with `ORDINAL`, `encode_message` and `decode_message`; a reply decodes to
   `Result<MReply, CallError<E>>`, `E` the method's error enum or `core::convert::Infallible`.
4. `Client<T, C>` wraps `silica_idl_rt::ClientCore` (`From<T>`), one method per protocol method returning
   `Result<MReply, CallError<E>>` (the reply borrows the client's buffer). `Server<C>` has one method per protocol
   method returning `MReply`, or `Result<MReply, E>` when the method declares an error.
5. One module per protocol, named by the last name segment in `snake_case`, in
   `<segments in snake_case joined by _>.rs`, with `NAME` and `VERSION` constants.
6. The generator rejects, with file, line and column: a struct or enum named `C`, `Client`, `S`, `Server` or `T`; one
   named like a generated `MRequest` or `MReply`, or two methods generating one name; two variants with the same
   CamelCase name, or a variant named `unknown`.

## 3. The evolution check, and no capability in an appended field

An appended field may not carry a capability at any depth (`cap`, `cap<T>`, `endpoint<P>`, or an `option`, `array`
or struct containing one), because an older decoder can skip the bytes but cannot account for the capability they
index, and would reject the whole message (`Decoder::finish`: `UnusedCap`). A new capability travels in a new method.

`silica-idlc check-compat <old.idl> <new.idl>` enforces `spec/IDL.md` section 4: old items and variants keep their
relative order and kind, fields are only appended, `version` never decreases and increases on any change but doc
comments. It parses each file alone, prints one `ERROR: <file>:<line>:<col>: <message>` per violation (a removal at
the old file, anything else at the new), exits 1 on any, 0 when compatible, 2 on a usage error. Tests:
`idlc/tests/versioning.rs` (`additive_only`, `version_skew`). `tools/check-protocols.sh` runs it against the shipped
protocols.

A retirement (the last step of a staged migration before the first `stable` release, `spec/IDL.md` section 4) is
checked by `check-compat --retire`: a method may be replaced by `reserved` at its ordinal, and a struct or enum
removed; a method removed without its ordinal reserved is an error, and every other rule holds, so nothing changes
unchecked beside the removal. A protocol is retired whole by reserving every method; its file is kept, and
`tools/check-protocols.sh` refuses a published file that is gone (with the file gone a protocol of the same name
could give the ordinals to other methods). Retirements are allowed before M9 only. Tests: `idlc/tests/versioning.rs`
(`a_method_is_retired_into_its_reserved_ordinal`), `os/tools/tests/protocol_compat.sh`.
An enum value a request carries and this version does not know is refused as an unknown field is
(`DecodeError::UnknownValue`, status `unknown_field`); in a reply it stays `Unknown(raw)`.

## 4. Known-answer vectors for the wire format

Round-trip tests cannot catch a symmetric layout error (big-endian on both encode and decode passed them all). So
`spec/IDL.md` section 3.1 lists normative byte vectors written from the prose, never from the encoder, and
`idlc/tests/wire_vectors.rs::known_answer_vectors` encodes and decodes each. Where the code and a vector disagree, the
code is wrong; a wrong vector is corrected in `spec/IDL.md` first, in a commit that shows the error from section 3.
Every later binding (libsys, C) reuses the vectors as its first conformance test.

## 5. Capability types, ownership and oversized replies in the transport

1. **Object type check in decoding.** `Capability::object_type(&self) -> Option<&str>` returns the kernel object type
   the transport learned on receipt. A `cap<T>` whose capability reports another type is malformed
   (`malformed_request` for a request, `malformed_reply` for a reply); `endpoint<P>` checks only that it is an
   Endpoint; `cap` is never checked. A typed field whose capability reports no type (`None`: the transport could
   not tell) is malformed too (`DecodeError::CapTypeUntold`): it is not known to be what the field declares, and
   a check that let it pass would fail open for exactly the capabilities nobody could inspect.
2. **Move semantics.** `Capability` is not `Clone`, because kernel transfer moves capabilities.
   `Transport::call(&mut self, message: &mut [u8], len: usize, caps: CapList<C>, reply_caps: &mut CapList<C>)`
   takes the request's capabilities by value and writes the reply over `message`, one buffer per client (not the
   thread's IPC buffer, which every client of a thread shares). From the call on, the transport owns the
   capabilities; a `too_large` request drops them.
3. **Oversized reply.** When a reply does not fit, `dispatch` releases its capabilities and sends status 4
   `reply_too_large` with an empty payload; `dispatch` returns `usize` and cannot fail.

## 6. Moved capabilities in generated Rust

1. **Encoding takes values by value:** `encode(&self, e)` writes bytes and capability indices; `move_caps(self,
   caps)` then moves the capabilities into the list in the same order. A failed encode drops the value.
2. **Decoding takes the capability list by value:** `decode_message(msg, caps: CapList<C>)`, `decode_request` and
   `decode_reply` move each referenced capability out and release the rest. `Decoder<'a, 'c, C>`; `Decode` takes
   `&mut Decoder<'a, '_, C>`.
3. **Object type check:** a `cap<T>`, `endpoint<P>` or an `option` of one decodes through `Decoder::cap(Some(name))`;
   plain `cap` passes `None`; a mismatch is `DecodeError::CapType`.
4. **No capability inside an `array`:** an `array<T>` whose `T` can carry a capability is refused by the language
   (`spec/IDL.md` section 2, `idlc/src/check.rs`), so every backend inherits it: in Rust an array is a borrowed
   slice or a view, which cannot own moved capabilities, and on the wire array elements decode without them. Use
   up to four `option<cap<T>>` fields.
5. **Derives:** a struct with `C` only through arrays gets hand-written `Clone`, `PartialEq` and `Debug` that do not
   require them of `C`; one that carries a capability derives them.
6. **`dispatch(server, request, caps: CapList<C>, reply, reply_caps) -> usize`** always produces a reply:
   `unknown_method`, `malformed_request`, `unknown_field` or `reply_too_large` (`silica_idl_rt::status_reply`). A
   reply buffer shorter than the 16-byte header gets length 0, seen as `malformed_reply`.
7. **`ClientCore`** keeps no capability list between calls.

`idlc/tests/transport.rs` uses a non-`Clone` capability stand-in that counts live instances: no capability is
duplicated, lost or kept after a failed call, a too-large request or a too-large reply.
