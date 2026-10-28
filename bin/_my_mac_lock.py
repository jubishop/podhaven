"""Serialize My Mac test runs across every checkout and session on this Mac.

A second xcodebuild test that installs the PodHaven test host kills the host of a run already in progress."""

from contextlib import contextmanager
from datetime import datetime
import fcntl
import os
from pathlib import Path
import sys

INHERITED_FD = "PODHAVEN_MY_MAC_LOCK_FD"


def inherited(path):
    try:
        held = os.fstat(int(os.environ[INHERITED_FD]))
        lock = path.stat()
    except (KeyError, ValueError, OSError):
        return False
    return (held.st_dev, held.st_ino) == (lock.st_dev, lock.st_ino)


@contextmanager
def my_mac_lock(holder):
    """Wait for and hold the machine-wide lock; yield its descriptor for commands that must keep holding it."""
    path = Path.home() / ".cache/podhaven/my-mac-tests.lock"
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
            yield lock.fileno()
        finally:
            lock.truncate(0)
