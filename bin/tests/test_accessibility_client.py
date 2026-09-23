"""Exercise the hosted-test accessibility connection without platform dependencies."""

from concurrent.futures import ThreadPoolExecutor
import ctypes
from http.client import HTTPConnection
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


ROOT = Path(__file__).resolve().parents[2]
loader = importlib.machinery.SourceFileLoader('test_accessibility_service', str(ROOT / 'bin/with-test-accessibility'))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


class Client:
    def __init__(self):
        self.requests = []
        self.error = None

    def inspect(self, pid):
        self.requests.append(pid)
        if self.error:
            raise RuntimeError(self.error)


class NativeAccessibility:
    def __init__(self, children, identities=None, errors=None):
        self.children = children
        self.identities = identities or {}
        self.errors = errors or {}
        self.visited = []
        self.arrays = {}
        self.next_array = 100_000
        self.ax = SimpleNamespace(
            AXIsProcessTrusted=Mock(return_value=True),
            AXUIElementCreateSystemWide=Mock(return_value=0),
            AXUIElementCreateApplication=Mock(return_value=1),
            AXUIElementSetMessagingTimeout=Mock(return_value=0),
            AXUIElementCopyAttributeValue=Mock(side_effect=self.copy_children),
        )
        self.cf = SimpleNamespace(
            CFStringCreateWithCString=Mock(return_value=-1),
            CFArrayGetCount=Mock(side_effect=lambda array: len(self.arrays[array.value])),
            CFArrayGetValueAtIndex=Mock(side_effect=lambda array, index: self.arrays[array.value][index]),
            CFGetTypeID=Mock(return_value=1),
            CFArrayGetTypeID=Mock(return_value=1),
            CFEqual=Mock(side_effect=lambda left, right:
                         self.identities.get(left, left) == self.identities.get(right, right)),
            CFRelease=Mock(side_effect=self.release),
        )
        self.proc = SimpleNamespace(proc_pidpath=Mock(side_effect=self.process_path))

    def process_path(self, pid, buffer, size):
        buffer.value = b'/test/PodHaven.app/PodHaven'
        return len(buffer.value)

    def copy_children(self, element, key, result):
        self.visited.append(element)
        if element in self.errors:
            return self.errors[element]
        self.next_array += 1
        self.arrays[self.next_array] = self.children.get(element, [])
        ctypes.cast(result, ctypes.POINTER(ctypes.c_void_p))[0] = self.next_array
        return 0

    def release(self, value):
        if isinstance(value, ctypes.c_void_p):
            del self.arrays[value.value]

    def client(self):
        with patch.object(module.ctypes, 'CDLL', side_effect=[self.ax, self.cf, self.proc]):
            return module.AccessibilityClient()


class NativeTraversalTests(unittest.TestCase):
    def test_cycles_do_not_prevent_inspection_of_other_children(self):
        for children, identities, expected in (
            ({1: [1, 2]}, {}, [1, 2]),
            ({1: [2, 3], 2: [2, 3]}, {2: 1}, [1, 3]),
            ({1: [2, 3], 2: [1]}, {}, [1, 2, 3]),
        ):
            with self.subTest(children=children, identities=identities):
                native = NativeAccessibility(children, identities)
                native.client().inspect(123)
                self.assertEqual(native.visited, expected)
                self.assertEqual(native.arrays, {})

    def test_distinct_elements_still_obey_depth_and_node_limits(self):
        for children, count in (
            ({node: [node + 1] for node in range(1, 43)}, 41),
            ({1: list(range(2, 10002))}, 10000),
        ):
            with self.subTest(count=count):
                native = NativeAccessibility(children)
                with self.assertRaisesRegex(RuntimeError, 'inspection limit'):
                    native.client().inspect(123)
                self.assertEqual(len(native.visited), count)
                self.assertEqual(native.arrays, {})

    def test_native_error_after_a_cycle_is_not_hidden(self):
        native = NativeAccessibility({1: [1, 2]}, errors={2: -25204})
        with self.assertRaisesRegex(RuntimeError, 'AX error -25204'):
            native.client().inspect(123)
        self.assertEqual(native.arrays, {})


class AccessibilityClientTests(unittest.TestCase):
    def setUp(self):
        self.client = Client()
        with patch('socket.getfqdn', side_effect=AssertionError('Local tests must not perform DNS lookups')):
            self.server = module.LocalAccessibilityServer(('127.0.0.1', 0), module.request_handler(self.client, 'token'))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.close)

    def close(self):
        self.server.shutdown()
        self.thread.join()
        self.server.server_close()

    def request(self, value, token='token'):
        connection = HTTPConnection('127.0.0.1', self.server.server_port, timeout=5)
        try:
            connection.request('POST', '/' + token, body=json.dumps(value).encode())
            response = connection.getresponse()
            return response.status, response.read().decode()
        finally:
            connection.close()

    def test_request_waits_for_inspection_of_the_supplied_process(self):
        status, message = self.request({'pid': 123})
        self.assertEqual(status, 200)
        self.assertEqual(self.client.requests, [123])
        self.assertIn('inspected', message)

    def test_unknown_token_does_not_inspect_any_process(self):
        self.assertEqual(self.request({'pid': 123}, token='wrong')[0], 404)
        self.assertEqual(self.client.requests, [])

    def test_shared_process_is_initialized_once_for_multiple_hosted_windows(self):
        self.assertEqual(self.request({'pid': 123})[0], 200)
        self.assertEqual(self.request({'pid': 123})[0], 200)
        self.assertEqual(self.request({'pid': 456})[0], 200)
        self.assertEqual(self.client.requests, [123, 456])

    def test_concurrent_hosted_windows_all_complete_inspection(self):
        count = 64
        start = threading.Barrier(count)

        def request(_):
            start.wait(timeout=15)
            return self.request({'pid': 123})

        with ThreadPoolExecutor(max_workers=count) as pool:
            responses = list(pool.map(request, range(count)))

        self.assertEqual([status for status, _ in responses], [200] * count)
        self.assertEqual(self.client.requests, [123])

    def test_invalid_requests_do_not_inspect_any_process(self):
        for value in ({}, [], {'pid': True}, {'pid': -1}, {'pid': '123'}):
            with self.subTest(value=value):
                self.assertEqual(self.request(value)[0], 400)
        self.assertEqual(self.client.requests, [])

    def test_native_inspection_failure_is_reported_to_the_test(self):
        self.client.error = 'Accessibility inspection failed'
        status, message = self.request({'pid': 123})
        self.assertEqual(status, 400)
        self.assertEqual(message, self.client.error)
        self.client.error = None
        self.assertEqual(self.request({'pid': 123})[0], 200)
        self.assertEqual(self.client.requests, [123, 123])


if __name__ == '__main__':
    unittest.main()
