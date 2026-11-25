# IDL: grammar, wire format, evolution

The compiler (`silica-idlc`, A06) implements exactly this. Where this file is silent and the choice is visible
outside `idl`, make the choice and write it here. The reasons for these rules, their costs and how to reverse them
are in `spec/IDL_RATIONALE.md`.

## 1. Files

- One protocol per file, UTF-8, under `idl/protocols/`. Protocol `a.b.Name` lives in
  `protocols/a/b/name.idl` (last segment in `snake_case`).
- `//` starts a comment to end of line. `///` is a doc comment and attaches to the next protocol, item, field or
  variant. Doc comments are carried into generated code.
- Identifiers: `[A-Za-z_][A-Za-z0-9_]*`. Methods, fields and variants are `snake_case`; structs and enums are
  `CamelCase`; protocol name segments are `snake_case` except the last, which is `CamelCase`. The compiler rejects
  other spellings and Rust keywords.
- Integers: decimal or `0x` hexadecimal.

## 2. Grammar

```
file     = doc* "protocol" pname "version" int "{" item* "}"
pname    = ident ("." ident)*
item     = doc* (method | reserved | struct | enum)
method   = ident "@" int "(" fields? ")" "->" "(" fields? ")" ("error" ident)? ";"
reserved = "reserved" "@" int ";"
struct   = "struct" ident "{" fields? "}"
enum     = "enum" ident ":" ("u8" | "u16" | "u32") "{" variant ("," variant)* ","? "}"
variant  = doc* ident "=" int
fields   = field ("," field)* ","?
field    = doc* ident ":" type
type     = "u8" | "u16" | "u32" | "u64" | "i8" | "i16" | "i32" | "i64" | "bool"
         | "string" | "bytes"
         | "array" "<" type ">" | "option" "<" type ">"
         | "cap" ("<" objtype ">")? | "endpoint" "<" pname ">"
         | ident                                   (a struct or enum of this protocol)
objtype  = "Untyped" | "CapSpace" | "Thread" | "AddressSpace" | "Frame" | "Endpoint"
         | "Notification" | "SchedContext" | "Hw" | "Vcpu"
```

Semantic rules, each a compile error with file, line and column:

- `version` is at least 1. Method ordinals are 1 to 2^32-1, unique, and never equal a `reserved` ordinal.
- Names are unique within their scope (items in a protocol, fields in a list, variants in an enum).
- Enum values fit the declared width and are unique. The `error` of a method names an enum of the protocol.
- A struct may not contain itself, directly or through other structs (no recursive types).
- `cap` is a capability of any object type; `cap<T>` one of type `T`; `endpoint<P>` an Endpoint capability whose
  provider speaks protocol `P`. `P` must resolve within the set of files compiled together.
- There are only call/reply methods. The kernel has no one-way message; events are long-poll methods or a
  `cap<Notification>` plus a ring on a `cap<Frame>`.

## 3. Wire format

All integers are little-endian. There is no padding and no alignment. Every message is a header followed by a
payload.

**Header**, 16 bytes:

| Offset | Type | Field |
| --- | --- | --- |
| 0 | u32 | method ordinal: non-zero, except in a `malformed_request` reply to a request too short to carry one or carrying 0 |
| 4 | u16 | flags: bit 0 = reply; other bits zero (a set reserved bit is malformed) |
| 6 | u16 | status: 0 in every request; in a reply, see below |
| 8 | u32 | protocol version of the sender (informational; never a reason to reject) |
| 12 | u32 | payload length in bytes; header plus payload equals the message length exactly |

**Reply status**: 0 `ok` (payload is the result field list); 1 `error` (payload is the method's error enum
value, encoded as a one-field list); 2 `unknown_method` (empty payload); 3 `malformed_request` (empty payload);
4 `reply_too_large` (empty payload: the provider's reply did not fit the limits below,
`spec/IDL_RATIONALE.md` section 5). Other values are malformed.

**Payload**: the request parameters, the reply results, or the error, each encoded as a field list.

**Encoding of values**:

| Type | Encoding |
| --- | --- |
| field list (parameters, results, struct) | u32 body length, then each field in declaration order |
| `u8`..`u64`, `i8`..`i64` | fixed width, two's complement for signed |
| `bool` | one byte, 0 or 1; anything else is malformed |
| enum | its declared width |
| `string`, `bytes` | u32 length, then the bytes; a `string` must be valid UTF-8 |
| `array<T>` | u32 element count, then each element |
| `option<T>` | one byte, 0 (absent) or 1 (present, followed by `T`); anything else is malformed |
| `cap`, `cap<T>`, `endpoint<P>` | one byte: the index of the capability in the message's capability list |

**Capabilities** never appear as bytes. They travel in the kernel message's capability transfer (C09), in a
list next to the bytes. Capability indices must appear in encoding order 0, 1, 2, ... and every transferred
capability must be referenced exactly once; otherwise the message is malformed. Generated decoding checks the
object type of a `cap<T>` where the transport reports one (`Capability::object_type`), and that an `endpoint<P>` is
an endpoint; a mismatch is malformed. The protocol of an `endpoint<P>` is a contract, not checked. Capabilities
move: the sender gives them up when it sends (`spec/IDL_RATIONALE.md` section 5).

**Limits**: a message is at most 4000 bytes including the header (what one kernel message carries; larger data travels in a shared Frame) and carries at most 4 capabilities; field lists
nest at most 32 deep. Larger data travels in a `cap<Frame>` with offset and length fields. Raising a limit later is
additive; lowering one is not.

**Decoding** is total: any byte string and capability list either decodes or yields an error, never a panic, and
decoding allocates nothing (strings, bytes and arrays decode to views of the input). Every encoded value occupies
at least one byte, so a count larger than the remaining bytes is rejected before any loop. Encoding is canonical:
one value has one encoding for a given protocol version.

### 3.1 Known-answer vectors

These byte strings are normative. Every implementation of the wire format (`silica-idl-rt` and generated Rust,
later libsys and other bindings) must encode the values below to exactly these bytes and decode these bytes to
exactly these values. They were written from the text of section 3, not produced by any encoder
(`spec/IDL_RATIONALE.md` section 4). All use protocol `sample.Echo` (`idl/protocols/sample/echo.idl`),
sender version 1. Bytes are hexadecimal, 16 per row.

V1, `echo` request, `data` = `68 69` ("hi"), no capabilities, 26 bytes:

```
01 00 00 00 00 00 00 00 01 00 00 00 0a 00 00 00
06 00 00 00 02 00 00 00 68 69
```

V2, `echo` reply, status `ok`, `data` empty, 24 bytes:

```
01 00 00 00 01 00 00 00 01 00 00 00 08 00 00 00
04 00 00 00 00 00 00 00
```

V3, `echo_records` request with one `Record`: `kind` = `tagged`, `flag` = true, `a` = 0x12, `b` = 0x3456,
`c` = 0x789abcde, `d` = 0x0102030405060708, `e` = -2, `f` = -300, `g` = -70000, `h` = -5, `name` = "é"
(UTF-8 `c3 a9`), `blob` = `00 ff`, `tags` = ["x", ""], `parent` = present 0x1122334455667788; 94 bytes:

```
02 00 00 00 00 00 00 00 01 00 00 00 4e 00 00 00
4a 00 00 00 01 00 00 00 42 00 00 00 01 01 12 56
34 de bc 9a 78 08 07 06 05 04 03 02 01 fe d4 fe
90 ee fe ff fb ff ff ff ff ff ff ff 02 00 00 00
c3 a9 02 00 00 00 00 ff 02 00 00 00 01 00 00 00
78 00 00 00 00 01 88 77 66 55 44 33 22 11
```

V4, `echo_records` reply, status `error`, `EchoError.empty`, 24 bytes:

```
02 00 00 00 01 00 01 00 01 00 00 00 08 00 00 00
04 00 00 00 01 00 00 00
```

V5, `echo_caps` request, `frame` = capability 0, `peer` = present, capability 1, `any` = capability 2; three
capabilities transferred; 24 bytes:

```
03 00 00 00 00 00 00 00 01 00 00 00 08 00 00 00
04 00 00 00 00 01 01 02
```

V6, `echo_caps` reply, status `ok`, `frame` = capability 0, `peer` absent, `any` = capability 1; two capabilities
transferred; 23 bytes:

```
03 00 00 00 01 00 00 00 01 00 00 00 07 00 00 00
03 00 00 00 00 00 01
```

V7, reply to a request with ordinal 9, status `unknown_method`, 16 bytes:

```
09 00 00 00 01 00 02 00 01 00 00 00 00 00 00 00
```

V8, `echo` reply, status `reply_too_large`, 16 bytes (`spec/IDL_RATIONALE.md` section 5; tested in
`idl/idlc/tests/transport.rs`):

```
01 00 00 00 01 00 04 00 01 00 00 00 00 00 00 00
```

## 4. Evolution (between versions of one protocol)

A new version may only:

- add methods with new ordinals, structs and enums, anywhere among the old items;
- append fields at the end of a parameter list, result list or struct; an appended field needs a default: 0 for
  integers, `false`, empty `string`/`bytes`/`array`, absent `option`, an enum that declares a variant `= 0`, or a
  struct whose fields all have defaults; and its type may not carry a capability at any depth (no `cap`,
  `cap<T>`, `endpoint<P>`, nor an `option`, `array` or struct containing one: an older peer skips unknown bytes but
  not the capabilities they index, see section 3). A new capability travels in a new method;
- add enum variants, anywhere among the old ones;
- change doc comments.

It may not rename, reorder, retype or remove anything (old items and variants keep their relative order, and an
item keeps its kind), change an ordinal, an enum width or value, or a method's `error`. `version` never decreases;
it increases (by any amount) when anything other than doc comments changed. `silica-idlc check-compat <old.idl>
<new.idl>` enforces this: one `ERROR:` line with file, line and column per violation, exit 1 on any, 0 when
compatible, 2 on a usage error (`spec/IDL_RATIONALE.md` section 3).
Before the first `stable` release a removal follows the staged migration in `spec/ARCHITECTURE.md`
section 4, bypassing the check for that one commit; a removed method's ordinal becomes `reserved` forever.

How skew is tolerated, by construction:

- A decoder reads the fields it knows. If a field list's body is longer, it skips the rest (newer peer). If the body
  ends exactly between fields, the missing fields take their defaults (older peer). A body that ends inside a
  field is malformed.
- An unknown enum value decodes to an `Unknown(raw)` variant in generated code; it is not malformed.
- An unknown method ordinal gets a reply with status `unknown_method`.
- A reply carries the ordinal of its request. A request whose header is malformed gets `malformed_request` with the
  ordinal it carried, or 0 when it carried none; the provider answers every request, so its caller never waits on one.

## 5. What the caller observes (transport contract)

The native transport puts the byte length in the IPC label and sends that length rounded up
to whole words. The sender zeroes the unused bytes of the final word. Before copying bytes,
the receiver checks the label against its destination capacity, the 4000-byte limit, and the
word count delivered by the kernel. A mismatch produces `malformed_request` or `malformed_reply`.

Generated client calls return either the reply, the method's declared error, or a transport error. The transport
(libsys and the IDL runtime) reports, uniformly for every protocol:

| Transport error | When |
| --- | --- |
| `revoked` | the caller's endpoint capability was revoked or was never valid; also when revoked mid-call |
| `peer_gone` | the provider ended or restarted while the call was pending; its reply capability was destroyed |
| `cancelled` | the caller cancelled the pending call; a later reply from the provider is discarded |
| `too_large` | the request exceeds the limits of section 3 (detected before sending) |
| `malformed_reply` | the reply failed to decode |
| `unknown_method` | the provider does not implement the method (older provider) |
| `malformed_request` | the provider rejected the request as malformed |
| `reply_too_large` | the provider's reply exceeded the limits of section 3; it sent status 4 instead |

After `peer_gone` or `cancelled` the request may or may not have taken effect. Each method's doc comment states
whether retrying is safe. Each protocol's doc comments state what the caller observes in the `revoked`,
`peer_gone` and `cancelled` cases.

## 6. Compiler and generated Rust

- Crates in `idl`: `idlc` (`silica-idlc`: library and command line) and `rt` (`silica-idl-rt`: `no_std`, no
  `alloc`, `#![forbid(unsafe_code)]`; header, encoder, decoder, errors, the transport trait). Generated code depends
  only on `silica-idl-rt` and `core`.
- For each protocol the compiler generates one Rust module: the structs and enums; one request and one reply type
  per method with encode and decode; a client generic over the transport trait; a server trait with one method per
  protocol method, and a `dispatch` function that decodes a request, calls the server trait and encodes the reply
  (answering `unknown_method` and `malformed_request` itself). Capabilities are a type parameter of the runtime, so
  host tests use plain stand-in values.
- Output is a deterministic function of the input files.
- The Rust names and types of generated code, and the names the generator reserves, are fixed by
  `spec/IDL_RATIONALE.md` section 2, as amended by `spec/IDL_RATIONALE.md` section 5
  (capabilities are not `Clone` and move into `Transport::call`; `dispatch` cannot fail), and by
  `spec/IDL_RATIONALE.md` section 6 (encoding takes values by value, decoding takes the
  capability list by value, and generation rejects an `array` whose element type can carry a capability).
- How generated bindings reach other repositories (generated at build time or checked in) is decided when the
  first consumer (D03) exists, before M2.
