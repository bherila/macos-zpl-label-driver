import importlib.util
import io
import plistlib
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('usb_identity_probe', SCRIPTS / 'usb_identity_probe.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

# Synthetic throughout. No value here was read from a real device.
SERIAL = 'SYNTH0SERIAL'


def device(vendor=0x0A5F, product=0x00D1, serial=SERIAL, name='ZTC Synthetic (EPL)', interfaces=(0,)):
    """One device node shaped the way macOS publishes it, interface children included."""
    node = {'IOObjectClass': 'IOUSBHostDevice', 'idVendor': vendor, 'idProduct': product,
            'bDeviceClass': 0, 'USB Product Name': name, 'sessionID': 12345, 'locationID': 678}
    children = []
    for number in interfaces:
        child = {'IOObjectClass': 'IOUSBHostInterface', 'idVendor': vendor, 'idProduct': product,
                 'bInterfaceClass': 7, 'bInterfaceNumber': number, 'USB Product Name': name}
        if serial is not None:
            child['USB Serial Number'] = serial
        children.append(child)
    node['IORegistryEntryChildren'] = children
    if serial is not None:
        node['USB Serial Number'] = serial
        node['kUSBSerialNumberString'] = serial
    return node


def run(nodes, *argv):
    out = io.StringIO()
    code = probe.main(list(argv), stdin=io.BytesIO(plistlib.dumps(nodes)), stdout=out)
    return code, out.getvalue()


class USBIdentityProbeTests(unittest.TestCase):
    def test_the_serial_never_appears_in_any_output(self):
        for argv in ((), ('--fingerprint',)):
            code, text = run([device()], *argv)
            self.assertEqual(code, 0)
            self.assertNotIn(SERIAL, text)
            self.assertNotIn(SERIAL.lower(), text.lower())

    def test_a_usable_serial_is_reported_by_shape_only(self):
        code, text = run([device()])
        self.assertEqual(code, 0)
        self.assertIn('serial: PRESENT  length=12  classes=digits,upper  unit-distinct=yes', text)

    def test_one_printer_is_counted_once_despite_its_interface_copy(self):
        # macOS copies idVendor, idProduct and the serial onto the interface child, so a
        # key-only match reports one physical printer as two.
        code, text = run([device()])
        self.assertIn('1 USB device(s) visible, 1 from Zebra', text)
        self.assertEqual(text.count('serial: PRESENT'), 1)
        self.assertIn('printer-class interface(s): 0', text)

    def test_an_absent_serial_is_not_a_usable_identity(self):
        code, text = run([device(serial=None)])
        self.assertEqual(code, 1)
        self.assertIn('serial: ABSENT', text)

    def test_a_placeholder_serial_is_present_but_not_unit_distinct(self):
        for placeholder in ('00000000', '   ', ''):
            with self.subTest(placeholder=placeholder):
                code, text = run([device(serial=placeholder)])
                self.assertEqual(code, 1, 'a placeholder identifies no unit')
                self.assertIn('unit-distinct=NO', text)

    def test_the_fingerprint_is_opt_in_and_stable(self):
        _, default = run([device()])
        self.assertNotIn('fingerprint=', default, 'default output must be safe to post publicly')
        _, first = run([device()], '--fingerprint')
        _, second = run([device()], '--fingerprint')
        self.assertIn('fingerprint=', first)
        self.assertEqual(first, second)
        _, other = run([device(serial='SYNTH0OTHER1')], '--fingerprint')
        self.assertNotEqual(first, other, 'different units must not share a fingerprint')

    def test_session_scoped_values_do_not_move_the_fingerprint(self):
        # sessionID and locationID change on replug; the identity must not.
        moved = device()
        moved['sessionID'], moved['locationID'] = 99999, 11111
        _, before = run([device()], '--fingerprint')
        _, after = run([moved], '--fingerprint')
        self.assertEqual(before, after)

    def test_other_vendors_are_counted_but_never_described(self):
        other = device(vendor=0x05AC, product=0x0001, serial='PERSONALDEVICE1', name='Somebody\'s Phone')
        code, text = run([other, device()])
        self.assertIn('2 USB device(s) visible, 1 from Zebra', text)
        self.assertNotIn('Somebody', text)
        self.assertNotIn('PERSONALDEVICE1', text)
        self.assertNotIn('0x05AC', text)

    def test_no_zebra_device_is_measured_but_not_success(self):
        code, text = run([device(vendor=0x05AC)])
        self.assertEqual(code, 1)
        self.assertIn('0 from Zebra', text)

    def test_unreadable_input_is_exit_two_and_echoes_nothing(self):
        for raw in (b'', b'   \n', b'not a plist ' + SERIAL.encode()):
            with self.subTest(raw=raw[:12]):
                out = io.StringIO()
                self.assertEqual(probe.main([], stdin=io.BytesIO(raw), stdout=out), 2)
                self.assertNotIn(SERIAL, out.getvalue())

    def test_oversized_input_is_refused_at_the_cap(self):
        original = probe.MAXIMUM_INPUT_BYTES
        probe.MAXIMUM_INPUT_BYTES = 64
        try:
            self.assertEqual(probe.main([], stdin=io.BytesIO(plistlib.dumps([device()])),
                                        stdout=io.StringIO()), 2)
        finally:
            probe.MAXIMUM_INPUT_BYTES = original

    def test_an_unknown_option_is_refused(self):
        self.assertEqual(probe.main(['--print-serial'], stdin=io.BytesIO(b''), stdout=io.StringIO()), 2)


if __name__ == '__main__':
    unittest.main()
