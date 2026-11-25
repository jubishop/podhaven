"""Limit how many heavy validation runs do their work at once across every checkout and session on this Mac.

Each slot is an advisory file lock, so the system frees a slot when its holder exits or is killed. Take a slot
before the My Mac test lock, never while holding it, so runs that need both can't deadlock."""

from contextlib import contextmanager
from datetime import datetime
import fcntl
import os
from pathlib import Path
import re
import sys
import time

COUNT_VARIABLE = "PODHAVEN_VALIDATION_SLOTS"
DEFAULT_COUNT = 2
# Names the held slot's file and holder process, so a nested run reuses the slot even when it was started without
# the holder's descriptors, as managed bin/check starts bin/check-application.
HOLDER_VARIABLE = "PODHAVEN_VALIDATION_SLOT"
POLL_SECONDS = 1
SLOT_NAME = re.compile(r"validation-slot-[1-9]\d*\.lock")


def slot_paths():
    value = os.environ.get(COUNT_VARIABLE, str(DEFAULT_COUNT))
    if not re.fullmatch(r"[1-9]\d*", value):
        raise ValueError(f"{COUNT_VARIABLE} must be a positive integer, not {value!r}")
    directory = Path.home() / ".cache/podhaven"
    return [directory / f"validation-slot-{number}.lock" for number in range(1, int(value) + 1)]


def locked(path):
    """Report whether any open file, including another one in this process, holds the lock at path."""
    try:
        with path.open("r") as probe:
            fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return True
    except OSError:
        return False
    return False


def inherited(directory):
    """Report whether this process runs under the live holder of the slot that HOLDER_VARIABLE names."""
    pid, _, name = os.environ.get(HOLDER_VARIABLE, "").partition(":")
    path = Path(name)
    if not pid.isdigit() or path.parent != directory or not SLOT_NAME.fullmatch(path.name):
        return False
    try:
        record = path.read_text()
    except OSError:
        return False
    return record.startswith(f"pid {pid} since ") and locked(path)


def take(paths):
    """Return the open file of the first free slot, waiting without a time limit while every slot is held."""
    waited = False
    while True:
        for number, path in enumerate(paths, 1):
            lock = path.open("a+")
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                lock.close()
                continue
            if waited:
                print(f"Took validation slot {number}", file=sys.stderr, flush=True)
            return lock
        if not waited:
            holders = []
            for number, path in enumerate(paths, 1):
                try:
                    record = path.read_text().strip()
                except OSError:
                    record = ""
                holders.append(f"  slot {number}: {record or 'another run'}")
            print(f"Waiting for a validation slot ({COUNT_VARIABLE}={len(paths)}), held by:", *holders, sep="\n",
                  file=sys.stderr, flush=True)
            waited = True
        time.sleep(POLL_SECONDS)


@contextmanager
def validation_slot(holder):
    """Hold a validation slot and yield its descriptor, or None inside a process that already holds one.

    Exports HOLDER_VARIABLE so that nested runs reuse the slot instead of waiting on it."""
    paths = slot_paths()
    if inherited(paths[0].parent):
        yield None
        return
    paths[0].parent.mkdir(parents=True, exist_ok=True)
    with take(paths) as lock:
        lock.truncate(0)
        lock.write(f"pid {os.getpid()} since {datetime.now().astimezone():%Y-%m-%d %H:%M:%S %Z}: {holder}\n")
        lock.flush()
        os.environ[HOLDER_VARIABLE] = f"{os.getpid()}:{lock.name}"
        try:
            yield lock.fileno()
        finally:
            lock.truncate(0)
