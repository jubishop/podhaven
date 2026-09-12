"""Exercise the Swift workflow's diagnostic validation with real file fixtures."""

from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest

WORKFLOW = Path(__file__).resolve().parents[2] / ".github/workflows/swift-tests.yml"


class SwiftTestEvidenceTests(unittest.TestCase):
    def validate_evidence(self, bundle=True, log="xcodebuild output\n"):
        workflow = WORKFLOW.read_text()
        step = re.search(
            r"^      - name: Verify test evidence\n(.*?)(?=^      - |\Z)",
            workflow, re.M | re.S,
        )
        # The original workflow has no validation and lets partial evidence pass.
        script = ""
        if step:
            self.assertIn("        if: always()\n", step[1])
            script = textwrap.dedent(step[1].split("        run: |\n", 1)[1])
        with tempfile.TemporaryDirectory(prefix="swift evidence ") as directory:
            root = Path(directory)
            if bundle:
                (root / "TestResults.xcresult").mkdir()
                (root / "TestResults.xcresult/Info.plist").write_text("result metadata")
            if log is not None:
                (root / "xcodebuild.log").write_text(log)
            result = subprocess.run(
                ["bash", "-e", "-o", "pipefail", "-c", script], cwd=root,
                text=True, capture_output=True, timeout=5,
            )
            # Validation must leave available evidence intact for the upload.
            self.assertEqual((root / "TestResults.xcresult").is_dir(), bundle)
            self.assertEqual((root / "xcodebuild.log").exists(), log is not None)
            return result

    def test_complete_evidence_passes(self):
        result = self.validate_evidence()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_missing_or_empty_evidence_fails(self):
        for bundle, log, missing in (
            (False, "raw log", ["TestResults.xcresult"]),
            (True, None, ["xcodebuild.log"]),
            (False, None, ["TestResults.xcresult", "xcodebuild.log"]),
            (True, "", ["xcodebuild.log"]),
        ):
            with self.subTest(bundle=bundle, log=log):
                result = self.validate_evidence(bundle=bundle, log=log)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                for path in missing:
                    self.assertIn(path, result.stdout)

    def test_upload_remains_unconditional_after_validation_failure(self):
        step = re.search(
            r"^      - name: Retain test evidence\n(.*?)(?=^      - |\Z)",
            WORKFLOW.read_text(), re.M | re.S,
        )
        self.assertIsNotNone(step)
        self.assertIn("        if: always()\n", step[1])
        self.assertIn("            TestResults.xcresult\n", step[1])
        self.assertIn("            xcodebuild.log\n", step[1])


if __name__ == "__main__":
    unittest.main()
