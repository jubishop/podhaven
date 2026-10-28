"""Install the real local gate with disposable platform and suite commands."""

from pathlib import Path
import shutil
import sys

from test_test_all import FAKE as PLATFORM_FAKE

FAKE = PLATFORM_FAKE.replace("base / 'events'", "base / 'gate-events'")

ROOT = Path(__file__).resolve().parents[2]


def install_gate(repo, commands):
    """Return a disposable HOME; run the gate with it so its My Mac test lock stays out of the real one."""
    for name in ("test-all", "check-swift-results", "_my_mac_lock.py"):
        shutil.copy2(ROOT / "bin" / name, repo / "bin" / name)
    commands.mkdir(exist_ok=True)
    for path in (commands / "xcodebuild", commands / "xcrun", commands / "sw_vers",
                 repo / "bin/check", repo / "bin/lint-swift-format"):
        path.write_text(f"#!{sys.executable}\n" + FAKE)
        path.chmod(0o755)
    (repo / ".gitignore").write_text(".cache/\n")
    home = commands.parent / "home"
    home.mkdir(exist_ok=True)
    return home
