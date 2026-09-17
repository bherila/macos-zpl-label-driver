# Current implementation handoff — revision 3

Use the implementation accelerator in [ACCELERATOR.md](ACCELERATOR.md), then the
existing milestone sequence. This revision extends revision 2 without changing
the confirmed GC420d/USB/4x6/tear-off, Tahoe 26, MIT or local-signing baseline.

M0.1 bootstrap is recorded at
`d4dad6d32c0da501e48df45404a8e19b3377d5a9`: the public
`bherila/macos-zpl-label-driver` repository was created with `main` at that
commit after a staged disclosure scan. The repository name replaces the former
generic target throughout the handoff.

On 2026-09-15, the local Tahoe ARM host passed accelerator debug/release
validation (including 34 Python tests, 47 LabelCore tests, 132 independent
ZPL/PBM/analytic round-trips, and 15 inert CUPS ABI cases). LabelMac's Core
Graphics smoke passed in debug and release; the arm64 diagnostic built with a
26.0 deployment target, was ad-hoc signed, verified, and run inertly. These
facts advance M0 automated/native-signing evidence only; they do not establish
installed scheduler, option propagation, document fidelity, hardware, or
release acceptance.

Next safe slice is M1.1/M1.2 proof planning and execution only after explicit
authorization for a finite, clearly named experimental capture queue and its
installation scope. No printer output, queue modification, privileged helper,
or production adapter is authorized by the current evidence.

M1 preflight on Tahoe ARM is recorded in
[M1-TAHOE-CAPTURE-2026-09-15.md](validation/M1-TAHOE-CAPTURE-2026-09-15.md).
The candidate PPDs now pass native `cupstestppd -v` with standard full-bleed
media names, and the inert probe's release build/signature were verified. The
only attempted installation action was a non-interactive authorization check,
which was denied; no backend, queue, printer operation, or global CUPS change
occurred. M1 installed-scheduler evidence remains blocked until the local
supported administrator authorization path is completed.

Reusable components now exist: canonical monochrome packing/threshold/PBM, bounded
uncompressed graphic fields, copy ordering, an offline vector CLI, an inert CUPS
ABI probe, three candidate PPDs and original synthetic PDF/HTML fixtures. Do not
rewrite these as empty skeletons. Run the offline suite before and after changes.

The portable suite is tested on Linux in debug/release; Apple-specific targets
and all actual printing remain untested here. See [ACCELERATOR-VALIDATION.md](ACCELERATOR-VALIDATION.md).
The production PDF renderer, state-control layer, device coordinator/transport,
extraction engine/editor, installer and qualified printer profile are not implemented.

Installation, queue changes, hardware operations, merge and publication still need
the existing authorizations. The probe supports **only** a clearly named discard
queue; successful observation must never be called a printed label. Next high-value
experiment is native Tahoe scheduler admission/options and complete source capture.

After each slice, record the actual commit SHA, acceptance IDs advanced, tests run,
results, remaining evidence gates and next safe action. Do not fabricate a repository
commit hash for this preparation archive or convert partial tests into full acceptance.
