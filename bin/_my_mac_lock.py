"""Serialize My Mac test runs across every checkout and session on this Mac, and keep the display awake for them.

A second xcodebuild test that installs the PodHaven test host kills the host of a run already in progress, and
UIKit on the Mac sends every scene to the background while the displays sleep, which fails hosted tests."""

from contextlib import contextmanager
from datetime import datetime
import fcntl
import os
from pathlib import Path
import subprocess
import sys

INHERITED_FD = "PODHAVEN_MY_MAC_LOCK_FD"


def lock_path():
    return Path.home() / ".cache/podhaven/my-mac-tests.lock"


def inherited(path):
    try:
        held = os.fstat(int(os.environ[INHERITED_FD]))
        lock = path.stat()
    except (KeyError, ValueError, OSError):
        return False
    return (held.st_dev, held.st_ino) == (lock.st_dev, lock.st_ino)


def current_holder():
    """Return the record of the lock's holder, "" for a holder yet to record itself, or None while it is free."""
    try:
        with lock_path().open("r") as probe:
            try:
                fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return probe.read().strip()
    except OSError:
        pass
    return None


@contextmanager
def my_mac_lock(holder):
    """Wait for and hold the machine-wide lock and a display-sleep assertion; yield the lock's descriptor for commands
    that must keep holding it."""
    path = lock_path()
    if inherited(path):
        yield int(os.environ[INHERITED_FD])
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            lock.seek(0)
            print(f"Waiting for the My Mac test lock {path}, held by {lock.read().strip() or 'another run'}",
                  file=sys.stderr, flush=True)
            fcntl.flock(lock, fcntl.LOCK_EX)
            print("Took the My Mac test lock", file=sys.stderr, flush=True)
        lock.truncate(0)
        lock.write(f"pid {os.getpid()} since {datetime.now().astimezone():%Y-%m-%d %H:%M:%S %Z}: {holder}\n")
        lock.flush()
        try:
            # -u wakes a display that is already off; -w keeps the assertion until this process, or the command it
            # execs into, exits.
            with subprocess.Popen(["caffeinate", "-d", "-u", "-w", str(os.getpid())],
                                  stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL) as display:
                try:
                    yield lock.fileno()
                finally:
                    display.terminate()
        finally:
            lock.truncate(0)
