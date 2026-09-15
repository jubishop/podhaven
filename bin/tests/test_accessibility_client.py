"""Exercise the hosted-test accessibility connection without platform dependencies."""

from concurrent.futures import ThreadPoolExecutor
from http.client import HTTPConnection
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import threading
import unittest
from unittest.mock import patch


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
