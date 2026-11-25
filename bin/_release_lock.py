"""usage: python3 bin/_release_lock.py HOLDER COMMAND [ARG...]

Run a release command while holding the release lock that bin/testflight and bin/appstore share. The lock is in the
clone's common Git directory, so it covers every checkout: two release runs would pick the same build number from the
same tags. A held lock stops the command at once and names its holder. The command keeps the lock until it and every
process that inherited it exit; a nested release command, such as the upload bin/appstore runs, reuses it."""

from contextlib import contextmanager
from datetime import datetime
import fcntl
import os
from pathlib import Path
import subprocess
import sys

INHERITED_FD = "PODHAVEN_RELEASE_LOCK_FD"
HOLDER_PID = "PODHAVEN_RELEASE_LOCK_PID"


def lock_path(root):
    common = subprocess.check_output(["git", "-C", str(root), "rev-parse", "--path-format=absolute",
                                      "--git-common-dir"], text=True).strip()
    return Path(common) / "podhaven-release.lock"


def inherited(path):
    try:
        held = os.fstat(int(os.environ[INHERITED_FD]))
        lock = path.stat()
    except (KeyError, ValueError, OSError):
        return False
    return (held.st_dev, held.st_ino) == (lock.st_dev, lock.st_ino)


@contextmanager
def release_lock(root, holder):
    """Hold the release lock, or reuse an inherited one; yield its descriptor for commands that must keep holding it."""
    path = lock_path(root)
    if inherited(path):
        yield int(os.environ[INHERITED_FD])
        return
    with path.open("a+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            lock.seek(0)
            raise ValueError(f"Another release command holds {path}: {lock.read().strip() or 'unknown holder'}. "
                             "Wait for it to finish, then retry.") from error
        lock.truncate(0)
        lock.write(f"pid {os.getpid()} since {datetime.now().astimezone():%Y-%m-%d %H:%M:%S %Z}: {holder}\n")
        lock.flush()
        try:
            yield lock.fileno()
        finally:
            lock.truncate(0)


def main():
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    holder, command = sys.argv[1], sys.argv[2:]
    try:
        with release_lock(Path(__file__).resolve().parents[1], holder) as descriptor:
            os.set_inheritable(descriptor, True)
            os.environ[INHERITED_FD] = str(descriptor)
            # The command runs in this process, so it can tell that it holds the lock.
            os.environ[HOLDER_PID] = str(os.getpid())
            try:
                os.execv(command[0], command)
            except OSError as error:
                print(f"error: {command[0]}: {error.strerror}", file=sys.stderr)
                sys.exit(127)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
