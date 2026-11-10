"""Stop a hung tooling-test command without letting machine load decide a test's outcome.

Fixture commands start many fake commands, each a fresh interpreter, so a loaded machine can slow a run far
past its usual time although nothing hangs. HANG_LIMIT is long enough that only a real hang reaches it. Each
command starts in its own session, so a timeout kills every process it started, and waits for them to go,
before the test's temporary directories are cleaned up."""

import contextlib
import os
import signal
import subprocess
import time

HANG_LIMIT = 300


def start(args, **options):
    return subprocess.Popen(args, start_new_session=True, **options)


def run(args, *, input=None, capture_output=False, check=False, timeout=HANG_LIMIT, **options):
    """Run a command like subprocess.run, ending everything it started if it times out."""
    if input is not None:
        options["stdin"] = subprocess.PIPE
    if capture_output:
        options.update(stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    with start(args, **options) as process:
        stdout, stderr = finish(process, input, timeout)
    result = subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)
    if check:
        result.check_returncode()
    return result


def finish(process, input=None, timeout=HANG_LIMIT):
    try:
        return process.communicate(input, timeout=timeout)
    except BaseException:
        stop(process)
        raise


def wait(process, timeout=HANG_LIMIT):
    try:
        return process.wait(timeout)
    except BaseException:
        stop(process)
        raise


def kill(process):
    # Until the command itself is reaped, its process ID still names only its own group.
    if process.returncode is None:
        with contextlib.suppress(ProcessLookupError, PermissionError):
            os.killpg(process.pid, signal.SIGKILL)


def stop(process):
    """Kill the command and every process it started, returning once none remains."""
    if process.returncode is None:
        kill(process)
        process.wait()
        deadline = time.monotonic() + HANG_LIMIT
        while True:
            try:
                os.killpg(process.pid, 0)
            except ProcessLookupError:
                break
            except PermissionError:
                pass  # Only exited members remain, waiting to be reaped.
            if time.monotonic() > deadline:
                raise RuntimeError(f"Processes {process.args} started outlived SIGKILL for {HANG_LIMIT} s")
            time.sleep(0.01)
    for stream in (process.stdin, process.stdout, process.stderr):
        if stream:
            with contextlib.suppress(BrokenPipeError):
                stream.close()
