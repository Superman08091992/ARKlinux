"""Offline verifier invocation/logging tests; not a native image or boot proof."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'restart/native-ark-v0.1/build/build-image.sh'

class NativeUnitValidation(unittest.TestCase):
    def setUp(self):
        self.text=BUILD.read_text()
        self.tmp=tempfile.TemporaryDirectory()
        self.root=Path(self.tmp.name)
        match=re.search(r'^validate_guest_contract\(\)\{.*?^\}',self.text,re.M|re.S)
        self.assertIsNotNone(match)
        self.function=match[0]
        self.env=dict(os.environ,OUT=str(self.root/'out'),MNT='/unused-fixture')
    def tearDown(self):self.tmp.cleanup()
    def run_gate(self,check):
        self.env['TEST_CHECK']=check
        script='set -euo pipefail\narch-chroot(){ shift; "$@"; }\n'+self.function+'\nvalidate_guest_contract probe "$TEST_CHECK"\n'
        return subprocess.run(['bash','-c',script],env=self.env,text=True,capture_output=True,timeout=10)
    def test_failed_first_assertion_is_not_masked_by_later_success(self):
        result=self.run_gate('printf "unit-detail\\n" >&2; false; true')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('unit-detail',result.stdout+result.stderr)
        self.assertIn('unit-detail',(self.root/'out/evidence/contracts/probe.log').read_text())
        self.assertNotIn('ARK_GUEST_CONTRACT=PASS',result.stdout)
    def test_success_has_explicit_contract_marker(self):
        result=self.run_gate('test 1 = 1')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('ARK_GUEST_CONTRACT=PASS name=probe',result.stdout)
    def test_system_and_user_unit_managers_are_separate(self):
        line=next(l for l in self.text.splitlines() if l.startswith('validate_guest_contract systemd_units '))
        self.assertNotIn('/systemd/user/',line)
        self.assertNotIn('ark-agent@.service',line)
        self.assertIn('ark-agent@kenny.service',line)
        self.assertIn('ark-webull-executor.service',line)
        self.assertIn('systemd-analyze --user --man=no verify /etc/systemd/user/ark-embodied-desktop.service',self.text)
    def test_no_host_namespace_or_boot_proof_bypass(self):
        self.assertIn('unshare --mount --pid --fork --mount-proc --kill-child=SIGTERM',self.text)
        self.assertIn('mount --make-rprivate /',self.text)
        self.assertIn('SYSTEMD_LOG_TARGET=console',self.text)
        self.assertIn('6.18.*',self.text)
        self.assertIn('validate_guest_contract tradeanalyzer_boot_click',self.text)
        subprocess.run(['bash','-n',str(BUILD)],check=True)
    @unittest.skipUnless(shutil.which('systemd-analyze'),'systemd-analyze unavailable')
    def test_real_offline_user_verifier(self):
        unit=self.root/'probe.service'
        unit.write_text('[Unit]\nDescription=User verifier fixture\n[Service]\nExecStart=/usr/bin/true\n')
        result=subprocess.run(['systemd-analyze','--user','--man=no','verify',str(unit)],
                              env=dict(os.environ,XDG_RUNTIME_DIR=str(self.root),SYSTEMD_LOG_TARGET='console'),
                              text=True,capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

if __name__=='__main__':unittest.main(verbosity=2)
