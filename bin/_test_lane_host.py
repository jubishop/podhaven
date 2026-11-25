"""The second Mac's side of bin/test-all's remote lane, which bin/test-all sends over SSH to /usr/bin/python3 -c.

It runs under the host's Python 3.9, so it uses nothing newer.

probe prints, as one JSON line, who holds the host's desktop, whether FileVault is on, whether the desktop session
takes commands, and the host's Xcode, Swift, and macOS versions, so bin/test-all can refuse the host. It also creates
the mirror that bin/test-all pushes the commit to.

run REVISION BASE HOLDER runs once lockf holds the host's scheduled-jobs lock. It records HOLDER in the lock file,
checks out REVISION in the lane's checkout with only that commit's files, points the lane's origin/HEAD at BASE, the
primary Mac's origin/HEAD, or at nothing when BASE is empty, so bin/check's whitespace check starts where it would
there, and runs that checkout's bin/test-all in the desktop session under nice. It prefixes each line of the run's output with 1 or 2 for the stream it came from and
writes it to stderr, then writes the run's evidence folder to stdout as a tar archive. bin/test-all writes a line to
stdin every few seconds; when stdin ends or goes quiet for HEARTBEAT_TIMEOUT_SECONDS, the connection is gone, so it
stops the run, and lockf then releases the lock."""

import json
import os
import pwd
import re
import shutil
import subprocess
import sys
import tarfile
import threading
import time
from datetime import datetime
from pathlib import Path

# Relative to the host's home folder. home-infra's jobs on the host take the same lock.
LOCK = "Library/Application Support/home-infra/mac-mini/scheduled-jobs.lock"
SIGNING_REQUEST = "Library/Application Support/home-infra/mac-mini/signing-renewal-requested"
LANES = "Library/Caches/podhaven/test-lanes"
MIRROR = LANES + "/mirror.git"
LANE = LANES + "/lane-1"
REFS = "refs/test-all/"
# The mirror keeps this many of the newest commits pushed to it, besides the one a run tests.
MIRROR_REFS = 20
HEARTBEAT_TIMEOUT_SECONDS = 120
STOP_GRACE_SECONDS = 20
EVIDENCE_LINE = re.compile(rb"^Test evidence: (.+)$")
HOMEBREW = ("/opt/homebrew/bin", "/usr/local/bin")
# Its owner is the user at the desktop.
CONSOLE = "/dev/console"
# Exit statuses besides bin/test-all's 0 and 1; lockf adds 75 for a held lock, and ssh 255 for a failed connection.
LANE_FAILED = 3
STOPPED = 4
WRITE = threading.Lock()


def say(message):
    write_line(b"2 ", message.encode() + b"\n")


def write_line(tag, line):
    # Once the connection is gone, output has nowhere to go, but the run still has to be stopped.
    with WRITE:
        try:
            sys.stderr.buffer.write(tag + line)
            sys.stderr.buffer.flush()
        except OSError:
            pass


def git(*args, cwd=None):
    result = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"git {' '.join(args)} failed: {(result.stderr or result.stdout).strip()}")
    return result.stdout.strip()


def desktop(user, command):
    """command in the desktop session, whose login keychain automatic login unlocked, under nice.

    Root can join that session; launchctl asuser alone can't. sudo -u resets the environment, so this passes PATH,
    with Homebrew's Python and Ruby ahead of the system's when PATH lacks them, and LANG."""
    path = os.environ.get("PATH", os.defpath).split(os.pathsep)
    path = [entry for entry in HOMEBREW if entry not in path] + path
    return ["sudo", "-n", "launchctl", "asuser", str(user.pw_uid), "sudo", "-n", "-H", "-u", user.pw_name,
            "env", "PATH=" + os.pathsep.join(path), "LANG=en_US.UTF-8", "nice", "-n", "10", *command]


def output_of(command):
    # Merged as bin/test-all reads its own toolchain, so the two Macs' versions compare alike.
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return result.returncode, result.stdout.strip()


def probe():
    user = pwd.getpwuid(os.getuid())
    home = Path.home()
    (home / LOCK).parent.mkdir(parents=True, exist_ok=True)
    if not (home / MIRROR / "HEAD").exists():
        (home / MIRROR).mkdir(parents=True, exist_ok=True)
        git("init", "--quiet", "--bare", str(home / MIRROR))
    console = pwd.getpwuid(os.stat(CONSOLE).st_uid).pw_name
    report = {"user": user.pw_name, "console": console}
    if console != user.pw_name:
        report["filevault"] = output_of(["fdesetup", "isactive"])[0] == 0
    else:
        status, text = output_of(desktop(user, ["true"]))
        report["desktop"] = "" if status == 0 else text or f"exit status {status}"
    report["xcode"] = output_of(["xcodebuild", "-hideShellScriptEnvironment", "-version"])[1]
    report["swift"] = output_of(["xcrun", "swift", "--version"])[1]
    report["macos"] = output_of(["sw_vers", "-productVersion"])[1]
    print(json.dumps(report))
    return 0


def prepare(revision, base):
    """Check out revision in the lane with only its files, keeping the lane's path, and so its DerivedData."""
    home = Path.home()
    mirror, lane = home / MIRROR, home / LANE
    try:
        git("checkout", "--quiet", "--detach", "--force", revision, cwd=lane)
    except (OSError, RuntimeError):
        # A missing or broken worktree, such as one whose mirror was made again, is made again.
        shutil.rmtree(lane, ignore_errors=True)
        git("worktree", "prune", cwd=mirror)
        git("worktree", "add", "--quiet", "--detach", "--force", str(lane), revision, cwd=mirror)
    git("clean", "-ffdxq", cwd=lane)
    if base:
        git("update-ref", "refs/remotes/origin/HEAD", base, cwd=mirror)
    else:
        git("update-ref", "-d", "refs/remotes/origin/HEAD", cwd=mirror)
    if git("rev-parse", "HEAD", cwd=lane) != revision or git("status", "--porcelain", cwd=lane):
        raise RuntimeError(f"the lane's checkout {lane} does not hold exactly {revision}")
    refs = git("for-each-ref", "--sort=-committerdate", "--format=%(refname)", REFS, cwd=mirror).split()
    stale = [ref for ref in refs if ref not in (REFS + revision, REFS + base)][MIRROR_REFS:]
    if stale:
        subprocess.run(["git", "update-ref", "--stdin"], cwd=mirror, check=True, text=True,
                       input="".join(f"delete {ref}\n" for ref in stale))
    subprocess.run(["git", "gc", "--auto", "--quiet"], cwd=mirror, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    return lane


def relay(stream, tag, evidence):
    for line in iter(stream.readline, b""):
        found = EVIDENCE_LINE.match(line.rstrip(b"\n"))
        if found and tag == b"1 ":
            evidence.append(Path(os.fsdecode(found[1])))
        write_line(tag, line if line.endswith(b"\n") else line + b"\n")


def watch_heartbeat(beats):
    try:
        while os.read(0, 1024):
            beats["last"] = time.monotonic()
    except OSError:
        pass
    beats["ended"] = True


def stop(process):
    """Stop the run's process group, which sudo keeps and root's processes from sudo share, so root signals it."""
    for name in ("TERM", "KILL"):
        subprocess.run(["sudo", "-n", "kill", "-" + name, "--", f"-{process.pid}"], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
        try:
            process.wait(timeout=STOP_GRACE_SECONDS)
            return
        except subprocess.TimeoutExpired:
            pass


def run(revision, base, holder):
    user = pwd.getpwuid(os.getuid())
    started = datetime.now().astimezone()
    (Path.home() / LOCK).write_text(f"{holder}, pid {os.getpid()}, since {started:%Y-%m-%d %H:%M %Z}\n")
    try:
        lane = prepare(revision, base)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        say(f"Could not prepare the second Mac's lane: {error}")
        return LANE_FAILED
    say(f"Running on the second Mac, {os.uname().nodename}: {lane}/bin/test-all at {revision}")
    beats = {"last": time.monotonic(), "ended": False}
    threading.Thread(target=watch_heartbeat, args=(beats,), daemon=True).start()
    evidence = []
    process = subprocess.Popen(desktop(user, [str(lane / "bin/test-all")]), cwd=lane, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    relays = [threading.Thread(target=relay, args=(stream, tag, evidence))
              for stream, tag in ((process.stdout, b"1 "), (process.stderr, b"2 "))]
    for thread in relays:
        thread.start()
    while process.poll() is None:
        quiet = time.monotonic() - beats["last"]
        if beats["ended"] or quiet > HEARTBEAT_TIMEOUT_SECONDS:
            say("bin/test-all's connection to the second Mac ended; stopping its run there"
                if beats["ended"] else f"bin/test-all on the primary Mac went {round(quiet)} seconds without a "
                                       "heartbeat; stopping its run there")
            stop(process)
            for thread in relays:
                thread.join(STOP_GRACE_SECONDS)
            return STOPPED
        time.sleep(1)
    for thread in relays:
        thread.join(STOP_GRACE_SECONDS)
    if evidence and evidence[-1].is_dir():
        with tarfile.open(fileobj=sys.stdout.buffer, mode="w|") as archive:
            for path in sorted(evidence[-1].iterdir()):
                archive.add(str(path), arcname=path.name)
        sys.stdout.buffer.flush()
    return process.returncode if process.returncode in (0, 1) else LANE_FAILED


def main():
    mode, *args = sys.argv[1:]
    if mode == "probe":
        return probe()
    if mode == "run":
        return run(*args)
    raise SystemExit(f"unknown mode {mode!r}")


if __name__ == "__main__":
    sys.exit(main())
