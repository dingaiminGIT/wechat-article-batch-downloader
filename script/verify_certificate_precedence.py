#!/usr/bin/env python3
"""Verify that an explicit desktop certificate outranks legacy mitmproxy files."""

import json
import os
import pathlib
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request


def free_port() -> int:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


if len(sys.argv) != 2:
    raise SystemExit("usage: verify_certificate_precedence.py /path/to/backend")

binary = pathlib.Path(sys.argv[1]).resolve()
if not binary.is_file():
    raise SystemExit(f"backend not found: {binary}")

with tempfile.TemporaryDirectory(prefix="mp-cert-precedence-") as temporary:
    root = pathlib.Path(temporary)
    home = root / "home"
    legacy = home / ".mitmproxy"
    legacy.mkdir(parents=True)
    # Deliberately invalid: an affected build selects these files and either
    # fails startup or leaves the configured desktop certificate absent.
    (legacy / "mitmproxy-ca-cert.pem").write_text("legacy certificate")
    (legacy / "mitmproxy-ca.pem").write_text("legacy private key")

    cert_dir = home / ".config" / "mp-article-batch-downloader" / "certs"
    certificate = cert_dir / "root-ca.pem"
    private_key = cert_dir / "root-ca-key.pem"
    api_port = free_port()
    proxy_port = free_port()
    while proxy_port == api_port:
        proxy_port = free_port()
    config = {
        "api": {"hostname": "127.0.0.1", "port": api_port, "protocol": "http"},
        "proxy": {
            "system": False,
            "hostname": "127.0.0.1",
            "port": proxy_port,
            "skipInstallRootCert": True,
        },
        "download": {"dir": str(root / "downloads"), "playDoneAudio": False},
        "mp": {"disabled": False, "refreshToken": "release-certificate-check"},
        "cert": {
            "name": "MP Article Batch Downloader Local CA",
            "file": str(certificate),
            "key": str(private_key),
        },
    }
    config_path = root / "config.yaml"
    config_path.write_text(json.dumps(config))
    log_path = root / "service.log"
    environment = dict(
        os.environ,
        HOME=str(home),
        MP_ARCHIVE_PARENT=str(os.getpid()),
        MP_ARCHIVE_DATA=str(root / "data"),
    )
    with log_path.open("w") as log:
        process = subprocess.Popen(
            [str(binary), "--config", str(config_path)],
            env=environment,
            stdout=log,
            stderr=log,
        )
        try:
            endpoint = f"http://127.0.0.1:{api_port}/api/desktop/info"
            for _ in range(100):
                if process.poll() is not None:
                    break
                try:
                    with urllib.request.urlopen(endpoint, timeout=0.5) as response:
                        json.load(response)
                    break
                except Exception:
                    time.sleep(0.1)
            else:
                raise AssertionError("backend did not become ready")

            if process.poll() is not None:
                raise AssertionError(f"backend exited with status {process.returncode}")
            for path in (certificate, private_key):
                if not path.is_file():
                    raise AssertionError(f"configured certificate file was not created: {path}")
            if "BEGIN CERTIFICATE" not in certificate.read_text():
                raise AssertionError("configured certificate is not PEM encoded")
            if "PRIVATE KEY" not in private_key.read_text():
                raise AssertionError("configured private key is not PEM encoded")
            if private_key.stat().st_mode & 0o077:
                raise AssertionError("configured private key is readable outside its owner")
            print(json.dumps({"explicit_certificate_precedence": "passed", "packaged_backend": str(binary)}))
        except Exception:
            log.flush()
            detail = log_path.read_text(errors="replace")[-4000:]
            if detail:
                print(detail, file=sys.stderr)
            raise
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
