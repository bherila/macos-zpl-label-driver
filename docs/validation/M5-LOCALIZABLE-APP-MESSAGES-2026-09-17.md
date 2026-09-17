# Localizable application messages

18 stored app messages/dialog strings now use Foundation String(localized:) lookup with unchanged English fallback: saved-job inspection, USB discovery, editor errors, setup storage error and preview export dialog. Release app build and27 focused release model tests passed exit0. No translations, another-language support, actual GUI layout/VoiceOver or acceptance pass claimed.

SwiftUI literal labels already use localized keys; plain String status values and AppKit panel properties needed explicit Foundation lookup. Static literal keys remain available for catalog extraction. The English fallback preserves redacted errors and uncertainty/cancellation semantics. No printer identifiers, error descriptions, label content or paths become localization keys.

Validation: three saved-job model tests and24 USB-discovery/editor tests passed, followed by/alongside the finite release setup-app build; all commands reported exit0. This is a straightforward presentation refactor, so no text-matching test was added. Build/test do not establish visual accessibility or translated-language behavior. A translation catalog and full localization audit remain future work before any additional language claim.

The integrated baseline report evaluates the preceding source checkpoint. This follow-on has only its stated focused checks; no full current-source result or per-ID ledger refresh is inferred.
