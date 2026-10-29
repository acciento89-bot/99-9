#!/usr/bin/env python3
"""CPU-only Android metadata/raw-file export-filter contract. No Godot or SDK run."""
import configparser, fnmatch, hashlib, json, os, pathlib, re, subprocess, unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
META = json.loads((ROOT / "docs/android-release-metadata.json").read_text())


def sections():
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.read(ROOT / "export_presets.cfg")
    return cfg


class AndroidReleaseSourceTests(unittest.TestCase):
    def test_only_expected_android_release_versions(self):
        cfg = sections()
        names = []
        for section in cfg.sections():
            if re.fullmatch(r"preset\.\d+", section) and cfg[section].get("platform") == '"Android"':
                names.append(cfg[section]["name"].strip('"'))
                options = cfg[section + ".options"]
                self.assertEqual(int(options["version/code"]), META["androidVersionCode"])
                self.assertEqual(options["version/name"].strip('"'), META["androidVersionName"])
                self.assertEqual(options["package/unique_name"].strip('"'), META["package"])
        self.assertEqual(names, META["androidPresetNames"])
        self.assertEqual(META["savedLiveMax"], 6)  # Actual historical provider proof.
        self.assertEqual(META.get("reservedUnpublishedVersionCodes"), [7])
        self.assertEqual(META["androidVersionCode"], max([META["savedLiveMax"]] + META["reservedUnpublishedVersionCodes"]) + 1)
        self.assertEqual(META["androidVersionCode"], 8)

    def test_ios_and_shared_project_bytes_preserved(self):
        ios = (ROOT / "export_presets.cfg").read_bytes().split(b"[preset.1]", 1)[0]
        self.assertEqual(hashlib.sha256(ios).hexdigest(), META["preservedIOSPresetSha256"])
        self.assertEqual(hashlib.sha256((ROOT / "project.godot").read_bytes()).hexdigest(), META["preservedProjectGodotSha256"])

    def test_original_license_bytes_and_android_include_filters(self):
        cfg = sections()
        for filename, expected in META["rawLicenseFiles"].items():
            path = ROOT / filename
            self.assertTrue(path.is_file(), "Original upstream licence missing")
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), expected)
            for section in cfg.sections():
                if re.fullmatch(r"preset\.\d+", section) and cfg[section].get("platform") == '"Android"':
                    include = cfg[section]["include_filter"].strip('"').split(',')
                    exclude = cfg[section]["exclude_filter"].strip('"').split(',')
                    self.assertTrue(any(fnmatch.fnmatchcase(filename, p.strip()) for p in include), (section, filename))
                    self.assertFalse(any(fnmatch.fnmatchcase(filename, p.strip()) for p in exclude), (section, filename))
                    self.assertIn("licenses/godot-iap-3.0.2/PROVENANCE.json", include)

    def test_selected_signer_requires_exact_new_code_and_name(self):
        workflow = (ROOT / META["sourceWorkflow"]).read_text()
        self.assertEqual(re.findall(r"EXPECTED_VERSION_CODE: '([0-9]+)'", workflow), [str(META["androidVersionCode"])] * 2)
        self.assertEqual(re.findall(r"EXPECTED_VERSION_NAME: ([0-9.]+)", workflow), [META["androidVersionName"]] * 2)
        self.assertIn("--xpath='/manifest/@android:versionName'", workflow)
        self.assertIn('test "$name" = "$EXPECTED_VERSION_NAME"', workflow)

    def test_actual_pre_sign_identity_checks_reject_wrong_manifest_values(self):
        workflow = (ROOT / META["sourceWorkflow"]).read_text()
        checks = [line.strip() for line in workflow.splitlines() if line.strip().startswith(('test "$package"', 'test "$code"', 'test "$name"'))]
        self.assertEqual(len(checks), 3)
        script = 'set -euo pipefail\n' + '\n'.join(checks)
        env = {**os.environ, 'package': META['package'], 'code': str(META['androidVersionCode']),
               'name': META['androidVersionName'], 'PACKAGE_NAME': META['package'],
               'EXPECTED_VERSION_CODE': str(META['androidVersionCode']), 'EXPECTED_VERSION_NAME': META['androidVersionName']}
        self.assertEqual(subprocess.run(['bash'], input=script, text=True, env=env, capture_output=True).returncode, 0)
        for delta in [{'package': 'de.example.other'}, {'code': '6'}, {'code': '7'}, {'code': '70'},
                      {'name': '1.1.0'}, {'name': '1.2.0-beta'}]:
            with self.subTest(delta=delta):
                self.assertNotEqual(subprocess.run(['bash'], input=script, text=True, env={**env, **delta}, capture_output=True).returncode, 0)


if __name__ == "__main__":
    unittest.main()
