"""Self-contained tests. No real serials or router backups are bundled."""
import gzip
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[1] / "vap120wd_backup_ssh_clone.py"
spec = importlib.util.spec_from_file_location("tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

FIREWALL = b"""config defaults
\toption forward 'REJECT'

config zone 'zone_wan_df_route'
\toption name 'wandfroute'
\toption input 'REJECT'
\toption forward 'REJECT'

config rule 'access_from_wan'
\toption name 'Management-From-Wan'
\toption src 'wandfroute'
\toption target 'REJECT'
\toption proto 'tcp'
\toption dest_port '80 443'
\toption enabled '1'

config rule 'telnet_lan_reject'
\toption name 'Reject-Telnet-From-Lan'
\toption src 'lan'
\toption proto 'tcp'
\toption dest_port '23'
\toption target 'REJECT'
\toption enabled '1'

config rule 'ssh_lan_reject'
\toption name 'Reject-SSH-From-Lan'
\toption src 'lan'
\toption proto 'tcp'
\toption dest_port '22'
\toption target 'REJECT'
\toption enabled '1'

config rule 'telnet_wan_reject'
\toption name 'Accept-Telnet-From-Wan'
\toption src 'wandfroute'
\toption proto 'tcp'
\toption dest_port '23'
\toption target 'REJECT'
\toption enabled '1'

config rule 'ssh_wan_reject'
\toption name 'Accept-SSH-From-Wan'
\toption src 'wandfroute'
\toption proto 'tcp'
\toption dest_port '22'
\toption target 'REJECT'
\toption enabled '1'
"""
SHADOW = (b"root:$1$fake$REDACTED:18822:0:99999:7:::\n"
          b"mosquitto:*:0:0:99999:7:::\n"
          b"admin:$1$fake$ANOTHER:18822:0:99999:7:::\n"
          b"http:*:0:0:99999:7:::\n")
PASSWORD = tool.serial_password("ABC123XYZ")


def create_encrypted(files):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w", format=tarfile.GNU_FORMAT) as tar:
        for name, data in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o600
            info.mtime = 1234567
            tar.addfile(info, io.BytesIO(data))
    return tool.encrypt_backup(gzip.compress(output.getvalue(), mtime=0), PASSWORD)


class TestBackupTool(unittest.TestCase):
    def setUp(self):
        self.original = create_encrypted({
            "etc/config/firewall": FIREWALL,
            "etc/shadow": SHADOW,
            "etc/config/dropbear": b"config dropbear\n\toption Port '22'\n",
        })
        shadow_ref = tool.patch_shadow(SHADOW).replace(
            b"admin:$1$fake$ANOTHER:", b"admin:$1$fake$CHANGED:")
        self.reference = create_encrypted({
            "etc/config/firewall": tool.patch_firewall(FIREWALL, "legacy-exact"),
            "etc/shadow": shadow_ref,
            "etc/config/dropbear": b"config dropbear\n\toption Port '22'\n",
        })

    def records(self, data):
        return tool.normalized_files(tool.read_members(tool.decrypt_backup(data, PASSWORD)))

    def test_serial_rotation(self):
        self.assertEqual(tool.serial_password("ABC123XYZ"), "IJK123FGH")
        with self.assertRaises(tool.BackupError):
            tool.serial_password("Bad password!")

    def test_lan_only(self):
        result, old, new, changed = tool.transform(self.original, PASSWORD, "lan-only")
        self.assertEqual(changed, ["etc/config/firewall"])
        self.assertIn(b"ssh_lan_accept", new)
        self.assertIn(b"telnet_wan_reject", new)
        self.assertIn(b"ssh_wan_reject", new)
        self.assertIn(b"\toption input 'REJECT'", new)
        self.assertNotEqual(old, new)
        original = self.records(self.original)
        after = self.records(result)
        self.assertEqual(original["etc/shadow"], after["etc/shadow"])
        self.assertEqual(original["etc/config/dropbear"], after["etc/config/dropbear"])

    def test_legacy_like_keeps_admin_hash(self):
        result, _, _, changed = tool.transform(self.original, PASSWORD, "legacy-like")
        self.assertEqual(changed, ["etc/config/firewall", "etc/shadow"])
        after = self.records(result)
        self.assertEqual(after["etc/config/firewall"][1],
                         self.records(self.reference)["etc/config/firewall"][1])
        self.assertIn(b"admin:$1$fake$ANOTHER", after["etc/shadow"][1])
        self.assertIn(b"root::0:", after["etc/shadow"][1])

    def test_legacy_exact_matches_reference(self):
        result, _, _, changed = tool.transform(self.original, PASSWORD, "legacy-exact",
                                               self.reference)
        self.assertEqual(changed, ["etc/config/firewall", "etc/shadow"])
        after = self.records(result)
        reference = self.records(self.reference)
        for name in changed:
            self.assertEqual(after[name][1], reference[name][1])
        self.assertEqual(after["etc/config/dropbear"],
                         self.records(self.original)["etc/config/dropbear"])

    def test_wrong_serial(self):
        with self.assertRaises(tool.BackupError):
            tool.transform(self.original, "WRONG", "lan-only")

    def test_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder) / "existing.tar.gz"
            out.write_bytes(b"keep-me")
            with self.assertRaises(FileExistsError):
                tool.write_new(out, b"overwrite")
            self.assertEqual(out.read_bytes(), b"keep-me")


if __name__ == "__main__":
    unittest.main()
