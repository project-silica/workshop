# ADR 0004: The Rust shape of IDL-generated code

Status: accepted. Made while implementing A06.02 (ADR 0001, mode `escalations`).

## Context

`spec/IDL.md` section 6 fixes what the generator emits (types, request and reply per method, client, server
trait, `dispatch`) and that it depends only on `silica-idl-rt` and `core`, but not the Rust names and types. Those
are visible to every repository that will consume bindings (first D03 at M2), so they are recorded here before
any consumer exists.

## Decision

1. IDL to Rust: integers and `bool` as themselves; `string` as `&'a str`; `bytes` as `&'a [u8]`; `array<T>` as
   `silica_idl_rt::Array<'a, T, C>` (built from a slice, decoded as a view that re-decodes on iteration);
   `option<T>` as `Option<T>`; `cap`, `cap<T>` and `endpoint<P>` as the capability parameter `C`, bounded by
   `silica_idl_rt::Capability`. A struct or message type takes `'a` and `C` only when a field needs them.
2. Each enum gets a final variant `Unknown(raw)` (section 4), `from_raw` and `raw`. Enum variant names are the
   IDL names in `CamelCase`.
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

## Consequences

- Decoding allocates nothing and generated code needs no `alloc`; a client holds two 4096-byte buffers.
- Rule 6 adds generator-level naming errors on top of `spec/IDL.md` section 2; no existing protocol hits them.
- `tests/round_trip.rs` in `idl/idlc` compiles the generated module of `sample.Echo` and exercises all of it.

## How to reverse

Every point is a generated name or type, so a change regenerates bindings; before M2 nothing consumes them.
After M2, a change is a breaking change of every consumer's source (not of the wire format) and goes through
`spec/REPOSITORIES.md` section 2 rule 3.
