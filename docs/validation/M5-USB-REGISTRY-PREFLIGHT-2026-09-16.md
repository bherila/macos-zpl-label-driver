# Read-only USB registry discovery preflight

Preparation for M5-AC01/09 only. No device identity, transport, GUI or hardware
acceptance is added. Product discovery remains unimplemented.

## Observed result

On macOS 26.6.2, build 25G83, ARM64, a native Swift probe compiled with the
installed macOS 26.5 SDK was run under a hard ten-second subprocess timeout.
It matched only `IOUSBHostDevice` and `IOUSBHostInterface` registry classes,
with caps of 256 devices and 4096 interfaces. Both matching calls returned
kernel success and null iterators: zero registered matching objects were exposed
to this execution context. The corrected probe exited 0 within the timeout.

The initial probe incorrectly passed a null iterator to `IOIteratorIsValid` and
reported registry change. Inspection of the installed public `IOKitLib.h`
contract established that successful matching may return a null iterator when
there are no matches. That initial diagnostic failure is not a macOS discovery
failure; the corrected probe handles the empty result without iterator calls.

No USB service connection was opened. No serial, URI, registry path, device name
or complete property table was read/exported. No device command or query was
sent. The candidate printer-interface path was not exercised because no
interfaces were returned. Empty matching is not proof that the reported printer
is disconnected, nor proof that a GC420d is unsupported. Host attachment and
service visibility must be observed separately; do not infer a stable identity.

## Public API provenance and finite reproduction

Use [R35](../REFERENCES.md#r35) and the installed SDK's public `IOKitLib.h` and
`usb/IOUSBHostFamilyDefinitions.h`. No commercial implementation was inspected;
no third-party implementation is incorporated by this diagnostic.

The narrow matching/counting boundary can be reproduced with this standalone
Swift program. It retrieves no device properties and opens no service connection.

```swift
import Foundation
import IOKit
import IOKit.usb
import Darwin

func count(_ serviceClass: String, limit: Int) throws -> Int {
    var iterator: io_iterator_t = 0
    let status = IOServiceGetMatchingServices(kIOMainPortDefault,
        IOServiceMatching(serviceClass), &iterator)
    guard status == KERN_SUCCESS else { throw NSError(domain: "Unavailable", code: 1) }
    guard iterator != 0 else { return 0 }
    defer { IOObjectRelease(iterator) }
    var total = 0
    while true {
        let entry = IOIteratorNext(iterator)
        if entry == 0 { break }
        IOObjectRelease(entry)
        total += 1
        guard total <= limit else { throw NSError(domain: "Limit", code: 1) }
    }
    guard IOIteratorIsValid(iterator) != 0 else { throw NSError(domain: "Changed", code: 1) }
    return total
}
do {
    print("registeredUSBHostDevices=\(try count(kIOUSBHostDeviceClassName, limit: 256))")
    print("registeredUSBHostInterfaces=\(try count(kIOUSBHostInterfaceClassName, limit: 4096))")
} catch {
    print("registryProbeFailed=true")
    exit(1)
}
```

Compile with `xcrun swiftc -target arm64-apple-macos26.0`, then execute the
resulting local binary with a hard subprocess timeout of ten seconds. Stop on
timeout/error rather than retrying indefinitely or loosening system policy.
Entry caps bound iteration, not a kernel call's wall-clock duration.

## Next implementation and evidence boundary

Add user-initiated native discovery with distinct empty/unavailable/changed/limit
outcomes. Treat printer-class interface metadata as an observation, not GC420d
capability qualification. Registry handles/entry IDs are session observations,
not durable physical identities. Selection must not fabricate a URI, authorize
installation, change the immutable printer profile or bypass confirmations.
Exercise metadata/selection on a host exposing the actual USB device before
binding a stable identity or selecting a transport. Keep serials and connection
details private. System-backend reuse remains dependent on the separate M1
contract/admission experiment; USB enumeration does not establish delivery/status.

## Concurrent validation checkpoint

Documentation-only follow-up validation: repository preflight passed; 67 Python,
173 LabelCore and 219 LabelMac debug tests passed with terminal exit 0. Product
source is unchanged from PR #59; its previously recorded full debug/release,
accelerator/signature/packaged-worker gate remains the source-code checkpoint,
not evidence that device discovery or installed printing is accepted.

PR #58 corrected hosted run 35093979617 passed exact `730d65b`. Downloaded logs
confirm 213 native tests debug/release, local-ad-hoc app verification and packaged
worker PBM/ZPL equality. Both review findings were addressed on the branch; no
third review or merge was requested. PR #59 run 35094427805 and first review
were confirmed live at exact `04202d9`; their results are not yet accepted.
