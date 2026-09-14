"""Exercise the Swift workflow's diagnostic validation with real file fixtures."""

import os
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

    def test_revision_guard_rejects_stale_checkout_and_wrong_pr_head(self):
        step = re.search(
            r"^      - name: Verify current revision\n(.*?)(?=^      - |\Z)",
            WORKFLOW.read_text(), re.M | re.S,
        )
        self.assertIsNotNone(step)
        script = textwrap.dedent(step[1].split("        run: |\n", 1)[1])
        with tempfile.TemporaryDirectory(prefix="swift revision ") as directory:
            root = Path(directory)

            def git(*args, input=None):
                return subprocess.check_output(
                    ["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid", *args],
                    cwd=root, input=input, text=True, stderr=subprocess.DEVNULL,
                ).strip()

            git("init", "--quiet")
            tree = git("hash-object", "-t", "tree", "--stdin", input="")
            base = git("commit-tree", tree, "-m", "base")
            head = git("commit-tree", tree, "-p", base, "-m", "PR head")
            merge = git("commit-tree", tree, "-p", base, "-p", head, "-m", "PR merge")
            git("checkout", "--quiet", "--detach", merge)
            for expected, pr_head, passes in (
                (merge, head, True), (merge, "", True),
                (base, head, False), (merge, "f" * 40, False),
            ):
                with self.subTest(expected=expected, pr_head=pr_head):
                    result = subprocess.run(
                        ["bash", "-e", "-o", "pipefail", "-c", script], cwd=root,
                        env={**os.environ, "EXPECTED_REVISION": expected, "PR_HEAD_REVISION": pr_head},
                        text=True, capture_output=True, timeout=5,
                    )
                    self.assertEqual(result.returncode == 0, passes, result.stdout + result.stderr)
            self.assertIn(merge, (root / "ci-revision.txt").read_text())

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
