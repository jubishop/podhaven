"""Check the MetricKit crash smoke fixture and its Sentry readback verification."""

import importlib.machinery
import importlib.util
import json
from pathlib import Path
import unittest

import service_guard

ROOT = Path(__file__).resolve().parents[2]
loader = importlib.machinery.SourceFileLoader("metrickit_smoke", str(ROOT / "bin/sentry-metrickit-smoke"))
spec = importlib.util.spec_from_loader(loader.name, loader)
smoke = importlib.util.module_from_spec(spec)
loader.exec_module(smoke)

BINARY_UUID = "791C1373-79E0-375C-BAD7-80FB93301058"
OFFSETS = [0xC66508, 0xC82C58, 0xC75238]
RUN = "controlled-run"
UPLOADER = "com.artisanalsoftware.PodHaven.metrickitsmoke@1.4.1+1"
NAMES = [name for name, _ in smoke.FUNCTIONS]


def fixture():
    sent = json.dumps(smoke.diagnostic(BINARY_UUID, OFFSETS), separators=(",", ":")).encode()
    frames = [{"package": "PodHaven", "inApp": True, "symbolicatorStatus": "symbolicated", "function": name}
              for name in NAMES]
    frames.append({"package": "libsystem_kernel.dylib", "inApp": False, "symbolicatorStatus": "missing"})
    context = dict.fromkeys(smoke.CONTEXT_KEYS)
    context.update(type="default", attribution="diagnostic_metadata", termination="watchdog",
                   appVersion=smoke.VERSION, appBuild=smoke.BUILD, osVersion=smoke.METADATA["osVersion"],
                   rawPayloadAttachment="included", rawPayloadBytes=len(sent))
    mechanism = {"type": "MXCrashDiagnostic", "handled": False, "synthetic": True,
                 "meta": {"signal": {"number": 9, "name": "SIGKILL"}}}
    tags = {"diagnostic-run": RUN, "metrickit-crash": "watchdog", "dist": smoke.BUILD,
            "release": f"{smoke.BUNDLE}@{smoke.VERSION}+{smoke.BUILD}"}
    event = {
        "entries": [{"type": "exception", "data": {"values": [
            {"mechanism": mechanism, "stacktrace": {"frames": frames}}]}}],
        "tags": [{"key": key, "value": value} for key, value in tags.items()],
        "contexts": {"metrickit_crash": context},
        "user": {"id": "sdk-installation", "geo": {"city": "Seattle"}},
        "title": NAMES[-1],
    }
    offline = {"entries": [{"callStacks": [{"frames": [{"binaryName": "libsystem_kernel.dylib", "symbol": None}] + [
        {"binaryName": "PodHaven", "symbol": f"{name}() (in PodHaven)"} for name in reversed(NAMES)]}]}]}
    return event, sent, offline


class MetricKitSmokeTests(unittest.TestCase):
    def test_fixture_roots_the_call_tree_at_the_crashing_frame(self):
        node = smoke.diagnostic(BINARY_UUID, OFFSETS)["callStackTree"]["callStacks"][0]["callStackRootFrames"][0]
        chain = []
        while node is not None:
            chain.append((node["binaryName"], node["offsetIntoBinaryTextSegment"]))
            node = (node.get("subFrames") or [None])[0]
        self.assertEqual(chain, [("libsystem_kernel.dylib", 0x1234)] + [("PodHaven", offset) for offset in reversed(OFFSETS)])

    def test_verify_accepts_symbolicated_frames_with_diagnostic_attribution(self):
        event, sent, offline = fixture()
        result = smoke.verify(event, sent, len(sent), sent, offline, UPLOADER, RUN)
        self.assertEqual(result["release"], f"{smoke.BUNDLE}@{smoke.VERSION}+{smoke.BUILD}")
        self.assertEqual(result["inAppFunctions"], NAMES)

    def test_verify_rejects_misattribution_unsymbolicated_frames_and_private_data(self):
        def uploader_release(event, sent, offline):
            return event, sent, offline, f"{smoke.BUNDLE}@{smoke.VERSION}+{smoke.BUILD}"

        def unsymbolicated(event, sent, offline):
            event["entries"][0]["data"]["values"][0]["stacktrace"]["frames"][0]["symbolicatorStatus"] = "missing"
            return event, sent, offline, UPLOADER

        def outermost_title(event, sent, offline):
            event["title"] = NAMES[0]
            return event, sent, offline, UPLOADER

        def email(event, sent, offline):
            event["user"]["email"] = "listener@example.com"
            return event, sent, offline, UPLOADER

        def extra_context(event, sent, offline):
            event["contexts"]["metrickit_crash"]["composedMessage"] = "runtime value"
            return event, sent, offline, UPLOADER

        def altered_attachment(event, sent, offline):
            return event, sent.replace(b"0x8badf00d", b"0x0badf00d"), offline, UPLOADER

        for mutate in (uploader_release, unsymbolicated, outermost_title, email, extra_context, altered_attachment):
            with self.subTest(mutate.__name__):
                event, sent, offline, uploader = mutate(*fixture())
                with self.assertRaises(AssertionError):
                    smoke.verify(event, sent, len(sent), fixture()[1], offline, uploader, RUN)


if __name__ == "__main__":
    unittest.main()
