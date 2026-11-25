"""bin/test-all's remote lane: run the suite on the second Mac that the Git config value podhaven.testHost names.

The value is an SSH destination, set outside the repository, which is public. bin/test-all probes the host, pushes
the exact commit to the host's mirror, and runs _test_lane_host.py there under the host's scheduled-jobs lock, which
lockf takes without waiting, so a held lock means a busy lane. The run's output streams back as it happens, and its
evidence comes back as a tar archive once it ends. While the run lasts, a heartbeat on the SSH session's input tells
the host the connection is alive."""

import contextlib
import json
import re
import shlex
import socket
import subprocess
import sys
import tarfile
import threading
from pathlib import Path

import _test_lane_host as host_side

CONFIG = "podhaven.testHost"
# ServerAlive ends the client when the host stops answering, and the host ends the run when the heartbeat stops.
SSH_OPTIONS = ("-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15",
               "-o", "ServerAliveCountMax=4")
PROBE_TIMEOUT_SECONDS = 120
PUSH_TIMEOUT_SECONDS = 900
HEARTBEAT_SECONDS = 15
# lockf's exit status when the lock is held.
BUSY = 75
UNREACHABLE = 255
EVIDENCE_LINE = re.compile(r"^Test evidence: (.+)$")
# xcodebuild's signing errors that a renewal on the host fixes, such as a profile a new extension needs.
SIGNING_FAILURE = re.compile(r"No profiles for|doesn't include signing certificate|requires a provisioning profile"
                             r"|No signing certificate")
SIGNING_LOGS = ("xcodebuild.log", "siri-performance.log", "opml-performance.log")


def configured_host(root, environment):
    result = subprocess.run(["git", "config", "--get", CONFIG], cwd=root, env=environment, capture_output=True,
                            text=True)
    return result.stdout.strip() or None


def last_line(text):
    lines = text.strip().splitlines()
    return lines[-1] if lines else "no output"


class SecondMac:
    def __init__(self, host, root, environment):
        self.host = host
        self.root = root
        self.environment = environment
        self.code = Path(host_side.__file__).read_text()
        self.holder = None

    def ssh(self, command):
        return ["ssh", *SSH_OPTIONS, self.host, command]

    def host_command(self, *args):
        return shlex.join(["/usr/bin/python3", "-c", self.code, *args])

    def refusal(self, report):
        """Return why this run can't use the host, or None when the host matches this Mac's toolchain."""
        try:
            result = subprocess.run(self.ssh(self.host_command("probe")), cwd=self.root, env=self.environment,
                                    stdin=subprocess.DEVNULL, capture_output=True, text=True,
                                    timeout=PROBE_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            return f"it did not answer within {PROBE_TIMEOUT_SECONDS} seconds"
        if result.returncode == UNREACHABLE:
            return f"it is unreachable: {last_line(result.stderr)}"
        try:
            facts = json.loads(result.stdout.strip().splitlines()[-1])
        except (ValueError, IndexError):
            return f"its probe failed with exit status {result.returncode}: {last_line(result.stderr)}"
        if facts.get("console") != facts.get("user"):
            return ("no one is logged in at its desktop"
                    + (", and FileVault is on, so it may still be locked" if facts.get("filevault") else ""))
        if facts.get("desktop"):
            return f"its desktop session refused a command: {last_line(facts['desktop'])}"
        for key, name in (("xcode", "Xcode"), ("swift", "Swift"), ("macos", "macOS")):
            if facts.get(key) != report[key]:
                return f"its {name} is {facts.get(key)!r}, not this Mac's {report[key]!r}"
        return None

    def push(self, *commits):
        """Send commits to the host's mirror, returning why that failed, or None."""
        environment = {**self.environment, "GIT_SSH_COMMAND": shlex.join(["ssh", *SSH_OPTIONS])}
        try:
            # The mirror refuses a push that updates one ref twice.
            result = subprocess.run(["git", "push", "--quiet", "--no-verify", f"{self.host}:{host_side.MIRROR}",
                                     *(f"+{commit}:{host_side.REFS}{commit}" for commit in dict.fromkeys(commits))],
                                    cwd=self.root, env=environment, stdin=subprocess.DEVNULL, capture_output=True,
                                    text=True, timeout=PUSH_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            return f"sending the commit to it took over {PUSH_TIMEOUT_SECONDS} seconds"
        if not result.returncode:
            return None
        # git's first line names the cause, such as the connection's or the mirror's; its last is generic advice.
        lines = result.stderr.strip().splitlines()
        return f"sending the commit to it failed: {lines[0].strip() if lines else 'no output'}"

    def attempt(self, revision, base, output):
        """Run bin/test-all in the host's lane unless another run holds the lane, which leaves self.holder naming it.

        Return None for a held lane, else the SSH session's exit status and the folder the host's run named for its
        evidence, whose files are now in output."""
        lock = '"$HOME"/' + shlex.quote(host_side.LOCK)
        holder = f"PodHaven bin/test-all from {socket.gethostname()} for {revision[:12]}"
        command = (f"lockf -s -k -t 0 {lock} {self.host_command('run', revision, base, holder)}; lane=$?; "
                   f"if [ $lane -eq {BUSY} ]; then printf 'busy: %s\\n' \"$(cat {lock})\" >&2; fi; exit $lane")
        process = subprocess.Popen(self.ssh(command), cwd=self.root, env=self.environment, stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        ended = threading.Event()

        def heartbeat():
            while True:
                try:
                    process.stdin.write(b"\n")
                    process.stdin.flush()
                except OSError:
                    return
                if ended.wait(HEARTBEAT_SECONDS):
                    return

        def extract():
            # A run that made no evidence sends none, and a damaged archive fails the check of the files' hashes.
            try:
                with tarfile.open(fileobj=process.stdout, mode="r|") as archive:
                    archive.extractall(output, filter="data")
            except (tarfile.TarError, OSError):
                pass
            finally:
                process.stdout.read()

        threads = [threading.Thread(target=heartbeat, daemon=True), threading.Thread(target=extract, daemon=True)]
        for thread in threads:
            thread.start()
        remote_output = None
        self.holder = None
        for raw in process.stderr:
            line = raw.decode(errors="replace").rstrip("\n")
            if line.startswith("busy: "):
                self.holder = line.removeprefix("busy: ") or "another run"
                continue
            stream, text = (line[0], line[2:]) if line[:2] in ("1 ", "2 ") else ("2", line)
            if stream == "1" and (found := EVIDENCE_LINE.match(text)):
                remote_output = found[1]
                text = f"Test evidence: {output}"
            elif remote_output:
                text = text.replace(remote_output, str(output))
            print(text, file=sys.stdout if stream == "1" else sys.stderr, flush=True)
        status = process.wait()
        ended.set()
        for thread in threads:
            thread.join()
        with contextlib.suppress(OSError):
            process.stdin.close()
        return None if status == BUSY else (status, remote_output)

    def request_signing_renewal(self, output):
        """Ask the host to renew its signing when the run's builds failed to sign, returning whether they did."""
        if not any(SIGNING_FAILURE.search(path.read_text(errors="replace"))
                   for path in (output / name for name in SIGNING_LOGS) if path.is_file()):
            return False
        request = '"$HOME"/' + shlex.quote(host_side.SIGNING_REQUEST)
        try:
            subprocess.run(self.ssh(f"touch {request}"), cwd=self.root, env=self.environment,
                           stdin=subprocess.DEVNULL, capture_output=True, timeout=PROBE_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            pass
        return True
