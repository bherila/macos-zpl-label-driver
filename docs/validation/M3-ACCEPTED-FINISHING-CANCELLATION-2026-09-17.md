# Durable accepted finishing cancellation request — 2026-09-17

Partial M3/M5 software. AcceptedFinishingCancellationStore authenticates a bounded nonempty
at-most256-byte token against the accepted snapshot digest using a fixed-length comparison.
It independently reopens the exact accepted record and requires complete job equality before
publishing an immutable cancellation request. The token is never persisted. Requests bind
accepted ID/digest, use their own private namespace, are at most1024 bytes and four records,
and are idempotent only for identical context. Publication barrier failure remains uncertain.

Cold observation revalidates durable context. Monitor construction validates once and returns
a value with no public constructor; subsequent polls read only the bounded request record,
rejecting corrupt or unsafe files. This permits eventual chunk/status-boundary polling without
reparsing the PDF. Missing request is not proof of hardware state. There is no clearing API.
A cancellation request cannot undo accepted bytes, resolve recorded attempt uncertainty,
authorize replay or send a device-wide cancellation command.

Nearest independent constraints: token authorization does not replace exact accepted-context
validation; cancellation never resolves a potential prior transmission; corrupt monitoring
state must fail closed. Twenty-three focused native cases passed exit0, including the prior20
and authorization/idempotence/cold-monitor/context/corruption/symlink/uncertain-publication
combinations. Authorization/context/record omissions each failed exit1 through expected assertions;
exact restored23-case suite passed exit0.
Full finite900-second Mac gate session54742 completed FULL_GATE_EXIT0:104Python,
281Core and349Mac debug/release;132 strict and180 ASCII oracle cases per mode; finite
benchmark/inert ABI/pipeline checks, ARM/minimum26 metadata, nested local ad-hoc
signatures, Developer-ID negative and packaged-worker PBM/ZPL equality. Local artifact:
artifacts/setup-app.8RRkkZ. Implementation checkpoint: d3889ba92d77b68f6251b8735a7a894fbd7225ed. Source publication pending.

Mandatory durable polling is integrated in both accepted coordinator entry points. A validated
monitor checks before execution, before/after each event and at final return under the one
finite budget. Existing intent remains a review veto even when cancellation is requested.
Twenty-five focused native cases passed exit0, including requests before admission and at
file/chunk/status boundaries; no callbacks follow the observed request. Cancellation cannot
undo bytes accounted before a chunk boundary. Polling omission failed exit1 through expected assertions; exact restored25 cases passed exit0.

Next: add recovery interpretation that preserves uncertainty. Installed scheduler, identified unit status/correspondence, retail
policy and physical printing remain NOT RUN. Frozen Part B remains unchanged. No printer I/O,
administrator action, merge or binary publication occurred.
