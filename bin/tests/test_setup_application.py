"""Run bin/setup-application in a disposable checkout and check the SSH keepalive it configures for Git."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import service_guard


ROOT = Path(__file__).resolve().parents[2]
KEEPALIVE = "ssh -o ServerAliveInterval=30"


class SetupApplicationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="podhaven setup ")
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.repo = self.base / "checkout"
        self.global_config = self.base / "global config"
        self.global_config.write_text("")
        # Git takes its SSH command from GIT_SSH_COMMAND, core.sshCommand, or GIT_SSH; none leaks in from here.
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.env.update(HOME=str(self.base / "home"), GIT_CONFIG_NOSYSTEM="1",
                        GIT_CONFIG_GLOBAL=str(self.global_config), PYTHONDONTWRITEBYTECODE="1")
        (self.repo / "bin").mkdir(parents=True)
        self.git("init", "--quiet", "--initial-branch=main")
        # Without PodHaven.xcodeproj, the Xcode preparation has nothing to do.
        for name in ("setup-application", "_worktrees.py", "_knowledge.py"):
            shutil.copy2(ROOT / "bin" / name, self.repo / "bin" / name)

    def git(self, *args, check=True):
        return subprocess.run(["git", *args], cwd=self.repo, env=self.env, text=True, capture_output=True,
                              check=check).stdout.strip()

    def setup_application(self, **env):
        result = subprocess.run([str(self.repo / "bin/setup-application")], cwd=self.repo,
                                env={**self.env, **env}, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def local_ssh_command(self):
        return self.git("config", "--local", "--get", "core.sshCommand", check=False)

    def test_keeps_ssh_connections_alive_when_no_ssh_command_is_configured(self):
        self.setup_application()
        self.assertEqual(self.local_ssh_command(), KEEPALIVE)
        # Running setup again keeps the setting it made.
        self.setup_application()
        self.assertEqual(self.local_ssh_command(), KEEPALIVE)

    def test_preserves_an_ssh_command_that_is_already_configured(self):
        own = "ssh -i ~/.ssh/podhaven"
        self.setup_application(GIT_SSH_COMMAND=own)
        self.assertEqual(self.local_ssh_command(), "")
        self.setup_application(GIT_SSH="/usr/bin/ssh")
        self.assertEqual(self.local_ssh_command(), "")
        self.git("config", "--global", "core.sshCommand", own)
        self.setup_application()
        self.assertEqual(self.local_ssh_command(), "")
        self.git("config", "--global", "--unset", "core.sshCommand")
        self.git("config", "--local", "core.sshCommand", own)
        self.setup_application()
        self.assertEqual(self.local_ssh_command(), own)


if __name__ == "__main__":
    unittest.main()
