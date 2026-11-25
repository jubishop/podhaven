"""Stand in for caffeinate, so tests that take the My Mac test lock never wake or hold the real display.

Like caffeinate -w, the stand-in holds until the process it waits on exits or it is terminated, and it creates
no assertion. While it holds, the process table shows it with the arguments it was given."""

from pathlib import Path
import subprocess
import sys

SCRIPT = r'''
import select, sys
args = sys.argv[1:]
queue = select.kqueue()
try:
    queue.control([select.kevent(int(args[args.index('-w') + 1]), select.KQ_FILTER_PROC, select.KQ_EV_ADD,
                                 select.KQ_NOTE_EXIT)], 1)
except ProcessLookupError:
    pass
'''


def install(directory):
    """Put the stand-in in directory, which a test puts ahead of the service guard on PATH."""
    path = Path(directory) / "caffeinate"
    path.write_text(f"#!{sys.executable}\n{SCRIPT}")
    path.chmod(0o755)


def holders(pid):
    """Return the process IDs of stand-ins that keep the display awake until pid exits."""
    table = subprocess.check_output(["ps", "-A", "-ww", "-o", "pid=,command="], text=True)
    return [int(line.split(None, 1)[0]) for line in table.splitlines()
            if line.endswith(f"/caffeinate -d -u -w {pid}")]
