import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import m5fans as m

class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.p = patch.object(m, 'ROOT', self.root); self.p.start()
        for n in m.NAMES:
            (self.root/n).mkdir()
            for k,v in {'mode':'auto','level':'2','rpm':'1500', 'rampup_curve':'', 'rampdown_curve':''}.items():
                (self.root/n/k).write_text(v)
    def tearDown(self):
        self.p.stop(); self.tmp.cleanup()
    def test_profile_isolated(self):
        m.apply_profile(['fan2'], 'cool')
        self.assertEqual(m.read(self.root/'fan2/mode'), 'curve')
        self.assertEqual(m.read(self.root/'fan2/rampup_curve'), '0,30,50,65,75')
        self.assertEqual(m.read(self.root/'fan1/mode'), 'auto')
    def test_missing_fan_rejected(self):
        for p in (self.root/'fan3').iterdir(): p.unlink()
        (self.root/'fan3').rmdir()
        with self.assertRaises(RuntimeError): m.fans('all')
    def test_partial_failure_restores_all(self):
        original = m.write
        def fail(n,k,v):
            if n == 'fan2' and k == 'rampup_curve': raise OSError('injected')
            original(n,k,v)
        with patch.object(m,'write',side_effect=fail):
            with self.assertRaises(OSError): m.apply_profile(list(m.NAMES),'cool')
        self.assertTrue(all(m.read(self.root/n/'mode') == 'auto' for n in m.NAMES))
    def test_hot_manual_full_and_restore(self):
        def tick(_):
            self.assertEqual(m.read(self.root/'fan1/level'),'5')
            raise KeyboardInterrupt
        with patch.object(m,'temperatures',return_value={'EC':85}), patch.object(m.time,'sleep',side_effect=tick):
            with self.assertRaises(KeyboardInterrupt): m.manual(['fan1'],40,60)
        self.assertEqual(m.read(self.root/'fan1/mode'),'auto')
    def test_missing_sensor_aborts_restores(self):
        with patch.object(m,'temperatures',side_effect=OSError('sensor missing')):
            with self.assertRaises(RuntimeError): m.manual(['fan1'],60,60)
        self.assertEqual(m.read(self.root/'fan1/mode'),'auto')
    def test_invalid_manual_never_writes(self):
        for pct,sec in [(0,60),(60,301),(60,0)]:
            with self.assertRaises(ValueError): m.manual(['fan1'],pct,sec)
        self.assertEqual(m.read(self.root/'fan1/level'),'2')

if __name__ == '__main__': unittest.main()
