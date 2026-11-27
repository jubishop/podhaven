"""Limit how many heavy validation runs do their work at once across every checkout and session on this Mac.

Each slot is an advisory file lock, so the system frees a slot when its holder exits or is killed. Waiting runs take
free slots in the order they began waiting: each holds the lock on a numbered ticket in the queue the same way, so a
waiter that exits or is killed leaves the queue at once. Take a slot before the My Mac test lock, never while holding
it, so runs that need both can't deadlock."""

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
QUEUE_NAME = "validation-queue"
SLOT_NAME = re.compile(r"validation-slot-[1-9]\d*\.lock")
TICKET_NAME = re.compile(r"([1-9]\d*)\.lock")


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


def record(holder):
    return f"pid {os.getpid()} since {datetime.now().astimezone():%Y-%m-%d %H:%M:%S %Z}: {holder}\n"


def holder_of(path):
    """Return the record of the slot's holder, "" for a held slot whose holder has yet to record itself, or None."""
    if not locked(path):
        return None
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def queued_tickets(queue):
    """Return the numbers of the tickets that live waiting runs hold, deleting the files of the others."""
    numbers = []
    for path in queue.iterdir():
        match = TICKET_NAME.fullmatch(path.name)
        if not match:
            continue
        if locked(path):
            numbers.append(int(match[1]))
        else:
            path.unlink(missing_ok=True)
    return numbers


def free_slot(paths):
    """Return the number and open file of the first slot this process could lock, or None while every slot is held."""
    for number, path in enumerate(paths, 1):
        lock = path.open("a+")
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            lock.close()
            continue
        return number, lock
    return None


def held_by(holder):
    """Describe a holder as holder_of returns it."""
    return "free" if holder is None else holder or "another run"


def queue_report(ahead):
    if not ahead:
        return "Next in line for a validation slot"
    return f"Queued behind {ahead} earlier waiting run{'s' if ahead > 1 else ''}"


class Place:
    """A run's place among the runs waiting for a validation slot, which it takes the first time it has to wait, and
    again behind every run then waiting if it has to wait after leaving.

    A run inside the live holder of a slot reuses that slot, so it takes no place and polls only its readiness."""

    def __init__(self, holder):
        self.paths = slot_paths()
        self.holder = holder
        self.directory = self.paths[0].parent
        self.queue = self.directory / QUEUE_NAME
        self.reused = inherited(self.directory)
        self.ticket = self.number = self.slot = None
        self.holders, self.ahead = (), 0

    def poll(self, ready=lambda: True):
        """Return whether the run holds its slot, in self.slot, taking a free one only when no live run that began
        waiting earlier still waits and ready() allows it. Otherwise hold a place in the queue, and record each slot's
        holder in self.holders and the number of runs waiting ahead in self.ahead."""
        if self.reused:
            return ready()
        if self.slot:
            return True
        self.queue.mkdir(parents=True, exist_ok=True)
        with (self.directory / f"{QUEUE_NAME}.lock").open("a") as gate:
            fcntl.flock(gate, fcntl.LOCK_EX)
            tickets = queued_tickets(self.queue)
            self.ahead = sum(self.number is None or number < self.number for number in tickets)
            self.slot = None if self.ahead or not ready() else free_slot(self.paths)
            if self.slot:
                self.leave()
                return True
            self.holders = tuple(holder_of(path) for path in self.paths)
            if not self.ticket:
                self.number = 1 + max(tickets, default=0)
                self.ticket = (self.queue / f"{self.number}.lock").open("w")
                fcntl.flock(self.ticket, fcntl.LOCK_EX)
                self.ticket.write(record(self.holder))
                self.ticket.flush()
        return False

    def leave(self):
        if not self.ticket:
            return
        # Unlink before unlocking: once unlocked, the name can pass to a later waiter's ticket, which this would delete.
        (self.queue / f"{self.number}.lock").unlink(missing_ok=True)
        self.ticket.close()
        self.ticket = self.number = None


def take(place):
    """Return the open file of the slot place takes, waiting without a time limit behind each live run that began
    waiting first.

    Runs from checkouts that predate the queue skip it, but take slots through the same locks, so none is shared."""
    shown = None
    try:
        while not place.poll():
            holders, ahead = place.holders, place.ahead
            # Report only after releasing the queue lock, which a write to a full output pipe could otherwise hold.
            if not shown:
                lines = [f"Waiting for a validation slot ({COUNT_VARIABLE}={len(holders)}), held by:",
                         *(f"  slot {number}: {held_by(held)}" for number, held in enumerate(holders, 1))]
                lines += [queue_report(ahead)] if ahead else []
            elif all(holders) and (holders, ahead) != shown:
                # A slot that changes hands is reported once its new holder has recorded itself.
                lines = [f"Validation slot {number} is now held by {held}"
                         for number, (held, before) in enumerate(zip(holders, shown[0]), 1) if held != before]
                lines += [queue_report(ahead)] if ahead != shown[1] else []
            else:
                lines = []
            if lines:
                print(*lines, sep="\n", file=sys.stderr, flush=True)
                shown = holders, ahead
            time.sleep(POLL_SECONDS)
    finally:
        place.leave()
    if shown:
        print(f"Took validation slot {place.slot[0]}", file=sys.stderr, flush=True)
    return place.slot[1]


@contextmanager
def validation_slot(holder, place=None):
    """Hold a validation slot and yield its descriptor, or None inside a process that already holds one.

    Takes the slot through place, when given, so a run that already waits keeps its place and a slot it took.
    Exports HOLDER_VARIABLE so that nested runs reuse the slot instead of waiting on it."""
    place = place or Place(holder)
    if place.reused:
        yield None
        return
    with take(place) as lock:
        lock.truncate(0)
        lock.write(record(holder))
        lock.flush()
        os.environ[HOLDER_VARIABLE] = f"{os.getpid()}:{lock.name}"
        try:
            yield lock.fileno()
        finally:
            lock.truncate(0)
