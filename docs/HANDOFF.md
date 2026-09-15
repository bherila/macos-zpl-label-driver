# Current implementation handoff — revision 3

Use the implementation accelerator in [ACCELERATOR.md](ACCELERATOR.md), then the
existing milestone sequence. This revision extends revision 2 without changing
the confirmed GC420d/USB/4x6/tear-off, Tahoe 26, MIT or local-signing baseline.

Next slice remains **M0.1**: reconcile/import the package into the actual target
repository without overwriting existing work. No current remote lookup or mutation
was performed during this revision. The older 404 is historical absent-or-inaccessible
evidence only. Continue M0 native CI and M1 scheduler/local-installation proof.

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
