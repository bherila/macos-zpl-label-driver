# Security policy

## Current status

Pre-release development scaffold. No production-supported release yet. Security defects block a public binary release.

Before public launch, the maintainer must enable GitHub private vulnerability reporting and verify the repository's Security > Report a vulnerability path. Until that is enabled, open a minimal issue requesting a private contact channel without including exploit details or sensitive print data. Do not invent or publish an unverified reporting email.

## Threat model

Treat PDFs, images, profiles, queue options, status replies, discovery results, transport endpoints and IPC messages as untrusted. Printing may involve privileged installation, but parsing and rendering must not require root. Privileged operations must be narrow, authenticated, authorized and resistant to path substitution/symlink races.

Routine logs exclude label pixels, barcode contents, usernames, document titles, serial numbers and private endpoints. Full diagnostic exports require explicit opt-in and a review screen. Files containing label contents are private, quota-bounded, short-lived and cleaned after success, cancellation or recovery. Failure cleanup must not erase unrelated files. Deletion is not a promise of forensic secure erasure on SSDs.

See docs/SECURITY-AND-PRIVACY.md for implementation gates. Do not disable operating-system protections to make a test pass. Local ad-hoc/source-build delivery is the active scope and must pass its own secure installation checks; it is not Developer-ID/notarized public distribution. See docs/LOCAL-SIGNING.md.
