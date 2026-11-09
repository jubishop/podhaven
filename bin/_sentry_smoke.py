"""Shared command, Sentry API, and script-loading helpers for the bin/sentry-*-smoke commands."""

from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def command(*args, **kwargs):
    return subprocess.check_output(args, cwd=ROOT, text=True, **kwargs).strip()


def load(name, path):
    loader = SourceFileLoader(name, str(path))
    module = module_from_spec(spec_from_loader(name, loader))
    loader.exec_module(module)
    return module


def api(path):
    response = json.loads(command("sentry", "api", path, "--json"))
    if response["status"] != 200:
        raise RuntimeError(f"Sentry API returned HTTP {response['status']} for {path}")
    return response["body"]
