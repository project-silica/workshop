# ADR 0009: Capability types, ownership and oversized replies in the IDL transport

Status: accepted. Answers the M0 gate major finding "IDL interfaces for M2" (`state/gates/M0.md`). It must be
implemented before M2 freezes libsys (C09.04, D03). Feature A06.04.

## Context

The M0 gate wrote an echo client and server from the documentation and the generated bindings alone. It managed,
but needed three workarounds, each traced to the runtime shape fixed by `spec/adr/0004-generated-rust-mapping.md`:

1. `cap`, `cap<T>` and `endpoint<P>` all become the one parameter `C`. No expected object type reaches the code
   that holds the received capability. `spec/IDL.md` section 3 says the transport checks the object type of a
   `cap<T>` where the kernel reports it, but nothing can.
2. `Transport::call` borrows `&CapList<C>`, and `ClientCore` then clears the caller's list. `Capability` requires
   `Clone`. Kernel capability transfer (C09) moves capabilities, and a kernel handle cannot be cloned for free.
3. Generated `dispatch` returns `Result<usize, EncodeError>`. A server whose reply exceeds the limits makes
   `dispatch` fail, but the provider has no legal reply to send, and the caller waits until `peer_gone` or
   `cancelled`.

Nothing consumes the bindings yet (ADR 0004, "How to reverse"), so changing them now costs one regeneration.

## Decision

1. **Object type check in decoding.** `silica_idl_rt::Capability` gets
   `fn object_type(&self) -> Option<&str>`. It returns the kernel object type name the transport learned on
   receipt (`"Frame"`, `"Endpoint"`, ...), or `None` when the kernel did not report one. When generated decoding
   reads the index of a `cap<T>` and the capability reports `Some(t)` with `t != "T"`, the message is malformed.
   A request is answered with `malformed_request`. A reply is reported to the caller as `malformed_reply`. `cap`
   is never checked. `endpoint<P>` checks only that the object is an `Endpoint`, because the protocol is a
   contract (section 3). Host stand-ins return `None` or a fixed name.
2. **Move semantics.** `Capability` no longer requires `Clone`. `Transport::call` takes the request
   capabilities by value: `call(&mut self, request: &[u8], caps: CapList<C>, reply: &mut [u8],
   reply_caps: &mut CapList<C>)`. From that call on, the transport owns them: it transfers them, or releases them
   when the call fails. Generated client methods take capability parameters by value. When a request is
   `too_large` (detected before `call`), the client drops the capabilities it was given, and the caller does not
   get them back. `ClientCore` never clears a list the caller still holds.
3. **Oversized reply.** Reply status 4 is `reply_too_large`, with an empty payload. When the server's reply does
   not fit the limits of section 3, generated `dispatch` releases the reply capabilities and encodes this status
   instead. `dispatch` returns `usize` and cannot fail: a header-only reply always fits. The caller observes the
   transport error `reply_too_large`. Section 3 and section 5 of `spec/IDL.md` are updated in the same commit as
   this ADR.

## Consequences

- Status 4 changes the wire format. That is allowed only because no consumer exists before M2. After M2 a new
  status would be malformed to older callers.
- The A06.02 vectors (section 3.1) are unchanged. A06.04 adds one vector-style test for a `reply_too_large`
  reply.
- Unknown: the exact kernel object type names come from the C09 and C-series capability specification. Until it
  exists, the names are the IDL names of the types used in `cap<T>`.

## How to reverse

Before M2, restore the ADR 0004 shapes and remove status 4. After M2, every point is a breaking change of
libsys and every consumer's source, and goes through `spec/REPOSITORIES.md` section 2 rule 3.
