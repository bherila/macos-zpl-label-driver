# Offline finishing inspection CLI — 2026-09-17

Partial application/CLI integration. label-driver finishing-inspect --catalog DIRECTORY
--accepted-id ID --accepted-sha SHA [--json] loads an exact verified original-PDF acceptance
and inspects conservative local recovery. Output is structured JSON; it contains hashes,
counts, canvas dimensions and local intent/cancellation, never source bytes, tokens, paths or
printer endpoint/status frames. Hardware completion is explicitly unknown; replay is disabled.
It sends no printer commands and publishes no job, intent or cancellation records.

Nearest independent constraint: inspecting local absence/uncertainty must not manufacture
hardware completion or fresh admission. Argument counts/lengths are bounded; missing or
unsafe catalogs are rejected before store construction. Root inode/device is checked again
before output. One finite operation budget covers accepted load and recovery.

Focused28 native cases passed exit0, including actual CLI success and digest mismatch
subprocesses (mismatch exit65, empty stdout, no catalog path in stderr). The added case checks original verified
record, no intent publication, explicit unknown hardware, prior intent plus cancellation,
no token/path fields, duplicate flags and missing-catalog rejection without creating it.
Intent/hardware/catalog guard faults each failed exit1 through expected assertions.
Recovery reads now open existing namespaces without creating them in both accepted intent
and cancellation stores. Both namespace-absence assertions fail when this shared option is
ignored. Exact restored28 cases passed exit0. Full finite900-second Mac gate session70662 completed FULL_GATE_EXIT0:104Python,
281Core and352Mac debug/release;132 strict and180 ASCII oracle cases per mode; finite
benchmark/inert ABI/pipeline checks, ARM/minimum26 metadata, nested local ad-hoc
signatures, Developer-ID negative and packaged-worker PBM/ZPL equality. Local artifact:
artifacts/setup-app.qYKkpi.
Source commit pending.

Prescribed scheduler/queue/USB/retail/physical I/H/R gates remain NOT RUN. Frozen Part B is
unchanged. No printer I/O, administrator action, merge or publication occurred.
