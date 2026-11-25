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


def leave(queue, place, ticket):
    # Unlink before unlocking: once unlocked, the name can pass to a later waiter's ticket, which this would delete.
    (queue / f"{place}.lock").unlink(missing_ok=True)
    ticket.close()


def queue_report(ahead):
    if not ahead:
        return "Next in line for a validation slot"
    return f"Queued behind {ahead} earlier waiting run{'s' if ahead > 1 else ''}"


def take(paths, holder):
    """Return the open file of a free slot, waiting without a time limit behind each live run that began waiting first.

    Runs from checkouts that predate the queue skip it, but take slots through the same locks, so none is shared."""
    directory = paths[0].parent
    queue = directory / QUEUE_NAME
    queue.mkdir(parents=True, exist_ok=True)
    ticket = place = shown = None
    try:
        while True:
            with (directory / f"{QUEUE_NAME}.lock").open("a") as gate:
                fcntl.flock(gate, fcntl.LOCK_EX)
                tickets = queued_tickets(queue)
                ahead = sum(place is None or number < place for number in tickets)
                taken = None if ahead else free_slot(paths)
                if taken and ticket:
                    leave(queue, place, ticket)
                    ticket = None
                elif not taken:
                    holders = tuple(holder_of(path) for path in paths)
                    if not ticket:
                        place = 1 + max(tickets, default=0)
                        ticket = (queue / f"{place}.lock").open("w")
                        fcntl.flock(ticket, fcntl.LOCK_EX)
                        ticket.write(record(holder))
                        ticket.flush()
            # Report only after releasing the queue lock, which a write to a full output pipe could otherwise hold.
            if taken:
                if shown:
                    print(f"Took validation slot {taken[0]}", file=sys.stderr, flush=True)
                return taken[1]
            if not shown:
                lines = [f"Waiting for a validation slot ({COUNT_VARIABLE}={len(paths)}), held by:",
                         *(f"  slot {number}: {'free' if held is None else held or 'another run'}"
                           for number, held in enumerate(holders, 1))]
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
        if ticket:
            leave(queue, place, ticket)


@contextmanager
def validation_slot(holder):
    """Hold a validation slot and yield its descriptor, or None inside a process that already holds one.

    Exports HOLDER_VARIABLE so that nested runs reuse the slot instead of waiting on it."""
    paths = slot_paths()
    if inherited(paths[0].parent):
        yield None
        return
    with take(paths, holder) as lock:
        lock.truncate(0)
        lock.write(record(holder))
        lock.flush()
        os.environ[HOLDER_VARIABLE] = f"{os.getpid()}:{lock.name}"
        try:
            yield lock.fileno()
        finally:
            lock.truncate(0)
