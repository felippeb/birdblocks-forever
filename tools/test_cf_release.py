#!/usr/bin/env python3
"""Offline tests for tools/cf_release.py.

No network, no token, no CurseForge account: the game-version endpoint and the
upload endpoint are both replaced by a throwaway local server, so the parts
that could publish to the wrong project are exercised before CI ever runs.

    python tools/test_cf_release.py
"""

from __future__ import annotations

import io
import json
import os
import sys
import tempfile
import threading
import unittest
import zipfile
from http.server import BaseHTTPRequestHandler, HTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cf_release as cf  # noqa: E402


# --------------------------------------------------------------------- helpers
def make_zip(path, entries):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, data in entries.items():
            zf.writestr(name, data)
    return path


GOOD = {
    "BirdBlocks/BirdBlocks.toc": "## Interface: 16001",
    "BirdBlocks/src/engine.lua": "return true",
    "BirdBlocks/tiles.tga": b"\x00\x01\x02",
}
ROOTS = ["BirdBlocks"]


class MockCF:
    """Collects the last request and replays a canned response."""

    def __init__(self):
        self.requests = []
        self.reply_status = 200
        self.reply_body = json.dumps({"id": 4242})
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def _payload(self):
                body = outer.reply_body
                if isinstance(body, (dict, list)):
                    return json.dumps(body).encode()
                return str(body).encode()

            def _record(self, method):
                length = int(self.headers.get("Content-Length", 0))
                outer.requests.append(
                    {"method": method, "path": self.path, "headers": dict(self.headers),
                     "body": self.rfile.read(length)}
                )

            def do_GET(self):
                self._record("GET")
                body = self._payload()
                self.send_response(outer.reply_status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_POST(self):
                self._record("POST")
                body = self._payload()
                self.send_response(outer.reply_status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        self.server = HTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_port}"
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.server.shutdown()
        self.server.server_close()


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def path(self, name):
        return os.path.join(self.tmp.name, name)

    def test_accepts_the_real_layout(self):
        roots = cf.check_archive(make_zip(self.path("ok.zip"), GOOD), ROOTS)
        self.assertEqual(roots, sorted(ROOTS))

    def test_rejects_wrapper_folder(self):
        bad = {"BirdBlocks-0.1.0/" + k: v for k, v in GOOD.items()}
        with self.assertRaises(cf.ReleaseError) as ctx:
            cf.check_archive(make_zip(self.path("wrapped.zip"), bad), ROOTS)
        self.assertIn("wrong archive root layout", str(ctx.exception))

    def test_rejects_missing_addon(self):
        partial = {"SomethingElse/x.lua": "x"}
        with self.assertRaises(cf.ReleaseError):
            cf.check_archive(make_zip(self.path("partial.zip"), partial), ROOTS)

    def test_rejects_folder_without_toc(self):
        toc_less = dict(GOOD)
        toc_less.pop("BirdBlocks/BirdBlocks.toc")
        toc_less["BirdBlocks/readme.txt"] = "x"
        with self.assertRaises(cf.ReleaseError) as ctx:
            cf.check_archive(make_zip(self.path("notoc.zip"), toc_less), ROOTS)
        self.assertIn("no .toc", str(ctx.exception))

    def test_rejects_nested_toc(self):
        # A TOC inside a subfolder does not load, so it must not count.
        nested = dict(GOOD)
        nested.pop("BirdBlocks/BirdBlocks.toc")
        nested["BirdBlocks/src/BirdBlocks.toc"] = "## Interface: 16001"
        with self.assertRaises(cf.ReleaseError) as ctx:
            cf.check_archive(make_zip(self.path("nested.zip"), nested), ROOTS)
        self.assertIn("no .toc", str(ctx.exception))

    def test_rejects_missing_file(self):
        with self.assertRaises(cf.ReleaseError):
            cf.check_archive(self.path("nope.zip"), ROOTS)


class VersionTests(unittest.TestCase):
    VERSIONS = [
        {"id": 111, "name": "1.15.5", "gameVersionTypeID": 1, "slug": "1-15-5"},
        {"id": 222, "name": "1.60.1", "gameVersionTypeID": 17, "slug": "1-60-1"},
        {"id": 333, "name": "11.0.5", "gameVersionTypeID": 1, "slug": "11-0-5"},
    ]

    def test_resolves_exact_name(self):
        self.assertEqual(cf.discover_game_version(self.VERSIONS, "1.60.1"), 222)

    def test_refuses_to_guess_between_duplicates(self):
        ambiguous = self.VERSIONS + [{"id": 444, "name": "1.60.1", "gameVersionTypeID": 99}]
        with self.assertRaises(cf.ReleaseError) as ctx:
            cf.discover_game_version(ambiguous, "1.60.1")
        self.assertIn("refusing to guess", str(ctx.exception))
        self.assertIn("444", str(ctx.exception))

    def test_lists_near_misses(self):
        with self.assertRaises(cf.ReleaseError) as ctx:
            cf.discover_game_version(self.VERSIONS, "1.60.2")
        message = str(ctx.exception)
        self.assertIn("1.60.1", message)
        self.assertNotIn("11.0.5", message)


class MetadataTests(unittest.TestCase):
    def test_shape(self):
        meta = cf.build_metadata("0.1.0", "alpha", "notes", [222])
        self.assertEqual(meta["gameVersions"], [222])
        self.assertEqual(meta["releaseType"], "alpha")
        self.assertEqual(meta["changelogType"], "markdown")
        self.assertNotIn("isMarkedForManualRelease", meta)

    def test_manual_release_flag(self):
        meta = cf.build_metadata("v", "beta", "notes", [222], manual_release=True)
        self.assertTrue(meta["isMarkedForManualRelease"])

    def test_rejects_unknown_release_type(self):
        with self.assertRaises(cf.ReleaseError):
            cf.build_metadata("v", "stable", "notes", [222])

    def test_rejects_empty_changelog(self):
        with self.assertRaises(cf.ReleaseError):
            cf.build_metadata("v", "alpha", "   \n", [222])

    def test_changelog_head_section(self):
        text = "# Changelog\n\n## 2.0 - now\n\n- b\n\n## 1.0 - before\n\n- a\n"
        self.assertEqual(cf.head_section(text), "## 2.0 - now\n\n- b")


class UploadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.zip = make_zip(os.path.join(self.tmp.name, "addon.zip"), GOOD)

    def test_multipart_puts_metadata_before_file(self):
        meta = cf.build_metadata("v1", "alpha", "notes", [222])
        boundary, body = cf.build_multipart(meta, self.zip)
        self.assertLess(body.index(b'name="metadata"'), body.index(b'name="file"'))
        self.assertIn(b'filename="addon.zip"', body)
        self.assertIn(json.dumps(meta).encode(), body)
        self.assertTrue(body.endswith(f"--{boundary}--\r\n".encode()))

    def test_upload_sends_token_and_returns_id(self):
        meta = cf.build_metadata("v1", "alpha", "notes", [222])
        with MockCF() as cf_mock:
            status, body = cf.upload(cf_mock.url, "1812870", "s3cret", meta, self.zip)
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["id"], 4242)

        request = cf_mock.requests[-1]
        self.assertEqual(request["method"], "POST")
        self.assertEqual(request["path"], "/api/projects/1812870/upload-file")
        headers = {k.lower(): v for k, v in request["headers"].items()}
        self.assertEqual(headers["x-api-token"], "s3cret")
        self.assertIn("multipart/form-data; boundary=", headers["content-type"])
        self.assertIn(b"notes", request["body"])
        self.assertIn(b"PK\x03\x04", request["body"])

    def test_upload_reports_http_error_without_raising(self):
        meta = cf.build_metadata("v1", "alpha", "notes", [222])
        with MockCF() as cf_mock:
            cf_mock.reply_status = 400
            cf_mock.reply_body = {"error": "bad metadata"}
            status, body = cf.upload(cf_mock.url, "1812870", "t", meta, self.zip)
        self.assertEqual(status, 400)
        self.assertIn("bad metadata", body)

    def test_discovery_hits_the_versions_endpoint(self):
        payload = VersionTests.VERSIONS
        with MockCF() as cf_mock:
            cf_mock.reply_body = payload
            versions = cf.http_json(f"{cf_mock.url}/api/game/versions", "s3cret")
        self.assertEqual(cf.discover_game_version(versions, "1.60.1"), 222)


class DryRunTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.zip = make_zip(os.path.join(self.tmp.name, "addon.zip"), GOOD)
        self.notes = os.path.join(self.tmp.name, "CHANGELOG.md")
        with open(self.notes, "w", encoding="utf-8") as handle:
            handle.write("## 0.1.0\n\n- first\n")

    def test_dry_run_touches_nothing(self):
        buffer = io.StringIO()
        stdout, sys.stdout = sys.stdout, buffer
        try:
            code = cf.main(
                [
                    "--file", self.zip,
                    "--version", "0.1.0",
                    "--changelog-file", self.notes,
                    "--dry-run",
                ]
            )
        finally:
            sys.stdout = stdout
        self.assertEqual(code, 0)
        output = buffer.getvalue()
        self.assertIn("top level:  BirdBlocks", output)
        self.assertIn("would resolve '1.60.1'", output)
        self.assertIn("nothing was uploaded", output)


if __name__ == "__main__":
    unittest.main(verbosity=2)
