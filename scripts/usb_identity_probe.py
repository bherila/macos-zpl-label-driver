#!/usr/bin/env python3
"""Read-only probe: does an attached USB printer publish a usable per-unit identity?

    ioreg -a -l -r -c IOUSBHostDevice | python3 scripts/usb_identity_probe.py

This reads an IORegistry property list on standard input and nothing else. It starts
no process, opens no device, claims no interface and sends no command, so it performs
no printer or USB I/O; the registry snapshot it is handed is host-side metadata of the
same kind `USBRegistryDiscovery` reads.

It never prints a serial number. A serial names one physical unit and must not reach a
log, an issue or a commit, so the report carries only what a decision needs: whether a
serial is published, its length, and which character classes it uses. That default
output is safe to paste publicly.

`--fingerprint` additionally prints a salted, truncated digest so two runs on one
machine can be compared across an unplug and replug. A serial is short and structured,
so treat the fingerprint as private too: compare it locally, do not commit or post it.

Exit status: 0 a Zebra device publishes a serial that looks unit-distinct; 1 measured,
but no Zebra device or no such serial; 2 the input could not be read as a property list.
"""
from __future__ import annotations

import hashlib
import plistlib
import re
import sys

ZEBRA_VENDOR_ID = 0x0A5F
PRINTER_INTERFACE_CLASS = 7
MAXIMUM_INPUT_BYTES = 16 * 1024 * 1024
SERIAL_KEYS = ('USB Serial Number', 'kUSBSerialNumberString')
FINGERPRINT_SALT = b'LABEL_USB_IDENTITY_PROBE_V1\n'


def devices_in(node, found=None):
    """Every USB *device* node, each once.

    macOS copies `idVendor`, `idProduct` and the serial onto a device's interface
    children, so matching on those keys alone counts one printer twice. A device node
    is the one that carries `bDeviceClass`; its interfaces carry `bInterfaceClass`.
    """
    if found is None:
        found = []
    if isinstance(node, dict):
        if 'idVendor' in node and 'idProduct' in node and 'bDeviceClass' in node:
            found.append(node)
        for child in node.get('IORegistryEntryChildren') or []:
            devices_in(child, found)
    elif isinstance(node, list):
        for item in node:
            devices_in(item, found)
    return found


def printer_interfaces(device):
    numbers = []
    for child in device.get('IORegistryEntryChildren') or []:
        if isinstance(child, dict) and child.get('bInterfaceClass') == PRINTER_INTERFACE_CLASS:
            numbers.append(child.get('bInterfaceNumber'))
    return numbers


def serial_of(device):
    for key in SERIAL_KEYS:
        value = device.get(key)
        if isinstance(value, str):
            return value
    return None


def shape(serial):
    classes = []
    if re.search(r'[0-9]', serial):
        classes.append('digits')
    if re.search(r'[A-Z]', serial):
        classes.append('upper')
    if re.search(r'[a-z]', serial):
        classes.append('lower')
    if re.search(r'[^0-9A-Za-z]', serial):
        classes.append('other')
    return ','.join(classes) or 'none'


def unit_distinct(serial):
    """A floor, not a uniqueness test: an empty or single-repeated-character serial
    (`00000000`) is a placeholder, and a placeholder identifies no unit."""
    stripped = serial.strip()
    return bool(stripped) and len(set(stripped)) > 1


def fingerprint(serial):
    return hashlib.sha256(FINGERPRINT_SALT + serial.encode('utf-8', 'replace')).hexdigest()[:12]


def report(root, with_fingerprint=False):
    lines, usable = [], 0
    devices = devices_in(root)
    zebra = [d for d in devices if d.get('idVendor') == ZEBRA_VENDOR_ID]
    lines.append(f'{len(devices)} USB device(s) visible, {len(zebra)} from Zebra (VID 0x0A5F)')
    for device in zebra:
        # The product string of a Zebra printer names a model, not a unit or a person.
        name = device.get('USB Product Name')
        name = name if isinstance(name, str) else '(no product string)'
        lines.append(f'  VID 0x{device["idVendor"]:04X}  PID 0x{device["idProduct"]:04X}  {name}')
        interfaces = printer_interfaces(device)
        lines.append('    printer-class interface(s): '
                     + (', '.join(str(n) for n in interfaces) if interfaces else 'none seen'))
        serial = serial_of(device)
        if serial is None:
            lines.append('    serial: ABSENT - no serial-number property is published')
            continue
        distinct = unit_distinct(serial)
        usable += distinct
        line = (f'    serial: PRESENT  length={len(serial)}  classes={shape(serial)}  '
                f'unit-distinct={"yes" if distinct else "NO - placeholder"}')
        if with_fingerprint:
            line += f'  fingerprint={fingerprint(serial)}'
        lines.append(line)
    return lines, usable


def main(argv=None, stdin=None, stdout=None):
    argv = sys.argv[1:] if argv is None else argv
    stdin = sys.stdin.buffer if stdin is None else stdin
    stdout = sys.stdout if stdout is None else stdout
    for flag in argv:
        if flag != '--fingerprint':
            print(f'unknown option {flag}', file=sys.stderr)
            return 2
    raw = stdin.read(MAXIMUM_INPUT_BYTES + 1)
    if len(raw) > MAXIMUM_INPUT_BYTES:
        print('CANNOT-READ input exceeds the size cap; refused rather than buffered', file=sys.stderr)
        return 2
    if not raw.strip():
        print('CANNOT-READ empty input: ioreg matched no entry of that class', file=sys.stderr)
        return 2
    try:
        root = plistlib.loads(raw)
    except Exception as error:  # plistlib raises several unrelated types
        # The type only: a parser message can echo bytes of the input.
        print(f'CANNOT-READ not a property list ({type(error).__name__})', file=sys.stderr)
        return 2
    lines, usable = report(root, with_fingerprint='--fingerprint' in argv)
    print('\n'.join(lines), file=stdout)
    return 0 if usable else 1


if __name__ == '__main__':
    raise SystemExit(main())
