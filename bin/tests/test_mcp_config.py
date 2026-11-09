"""Require each npx-launched MCP server to pin one exact package version across every agent configuration."""

import json
from pathlib import Path
import re
import tomllib
import unittest

import service_guard


ROOT = Path(__file__).resolve().parents[2]
PINNED = re.compile(r"(@?[^@\s]+)@(\d+\.\d+\.\d+)")


class MCPConfigTests(unittest.TestCase):
    def test_npx_servers_pin_one_exact_version_everywhere(self):
        servers = {
            ".mcp.json": json.loads((ROOT / ".mcp.json").read_text())["mcpServers"],
            ".cursor/mcp.json": json.loads((ROOT / ".cursor/mcp.json").read_text())["mcpServers"],
            ".codex/config.toml": tomllib.loads((ROOT / ".codex/config.toml").read_text())["mcp_servers"],
        }
        versions = {}
        for configuration, entries in servers.items():
            for name, server in entries.items():
                if server["command"] != "npx":
                    continue
                package = next(argument for argument in server["args"] if not argument.startswith("-"))
                with self.subTest(configuration=configuration, server=name):
                    pinned = PINNED.fullmatch(package)
                    self.assertIsNotNone(pinned, f"{package} must name an exact version")
                    versions.setdefault(pinned[1], set()).add(pinned[2])
        self.assertTrue(versions)
        for package, pins in versions.items():
            self.assertEqual(len(pins), 1, f"{package} pins differ: {sorted(pins)}")


if __name__ == "__main__":
    unittest.main()
