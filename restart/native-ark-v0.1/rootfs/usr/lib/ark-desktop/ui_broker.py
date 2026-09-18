#!/usr/bin/env python3
"""Local authorization and evidence broker for routine embodied navigation."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
from hashlib import sha256
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
import os
from pathlib import Path
import re
import secrets
import threading
import time
from typing import Any


ALLOWED_ACTIONS = {
    "close_window",
    "focus_search",
    "search",
    "open_url",
    "open_shell_app",
    "navigate_back",
}
ALLOWED_SHELL_APPS = {
    "console",
    "vault",
    "policy",
    "events",
    "system",
    "filesystem",
    "memory",
    "settings",
    "browser",
}
PLAN_ID = re.compile(r"^[A-Za-z0-9._:-]{1,128}$")
ZERO_HASH = "0" * 64


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


class BrokerError(Exception):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status


class EvidenceLedger:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.lock = threading.Lock()
        self.sequence, self.tip = self._verify()

    def _verify(self) -> tuple[int, str]:
        if not self.path.exists():
            return 0, ZERO_HASH
        expected_previous = ZERO_HASH
        expected_sequence = 1
        with self.path.open("r", encoding="utf-8") as stream:
            for line_number, line in enumerate(stream, 1):
                if not line.strip():
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError as error:
                    raise RuntimeError(f"invalid desktop ledger JSON at line {line_number}") from error
                observed_hash = record.pop("record_hash", "")
                calculated_hash = sha256(canonical(record)).hexdigest()
                if record.get("sequence") != expected_sequence:
                    raise RuntimeError(f"desktop ledger sequence break at line {line_number}")
                if record.get("previous_hash") != expected_previous:
                    raise RuntimeError(f"desktop ledger chain break at line {line_number}")
                if not secrets.compare_digest(observed_hash, calculated_hash):
                    raise RuntimeError(f"desktop ledger hash mismatch at line {line_number}")
                expected_previous = observed_hash
                expected_sequence += 1
        return expected_sequence - 1, expected_previous

    def append(self, event: str, payload: dict[str, Any]) -> str:
        with self.lock:
            record = {
                "sequence": self.sequence + 1,
                "timestamp_utc": datetime.now(timezone.utc).isoformat(),
                "event": event,
                "previous_hash": self.tip,
                **payload,
            }
            record_hash = sha256(canonical(record)).hexdigest()
            record["record_hash"] = record_hash
            encoded = canonical(record) + b"\n"
            descriptor = os.open(self.path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o660)
            try:
                written = 0
                while written < len(encoded):
                    written += os.write(descriptor, encoded[written:])
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
            self.sequence += 1
            self.tip = record_hash
            return f"desktop:{record_hash[:24]}"


@dataclass(frozen=True)
class PendingPermit:
    plan_id: str
    plan_digest: str
    issued_monotonic: float


class BrokerState:
    def __init__(self, ledger: EvidenceLedger, permit_ttl_seconds: int = 300) -> None:
        self.ledger = ledger
        self.permit_ttl_seconds = permit_ttl_seconds
        self.pending: dict[str, PendingPermit] = {}
        self.lock = threading.Lock()

    @staticmethod
    def validate_plan(plan: Any) -> dict[str, Any]:
        if not isinstance(plan, dict):
            raise BrokerError(HTTPStatus.BAD_REQUEST, "plan must be an object")
        plan_id = plan.get("planId")
        action = plan.get("action")
        if not isinstance(plan_id, str) or not PLAN_ID.fullmatch(plan_id):
            raise BrokerError(HTTPStatus.BAD_REQUEST, "invalid plan identifier")
        if action not in ALLOWED_ACTIONS:
            raise BrokerError(HTTPStatus.CONFLICT, "action is outside routine navigation")
        if plan.get("routine") is not True or plan.get("requiresApproval") is not False:
            raise BrokerError(HTTPStatus.CONFLICT, "action is not preauthorized routine navigation")
        if plan.get("source") != "deterministic-navigation":
            raise BrokerError(HTTPStatus.CONFLICT, "only deterministic navigation plans are accepted")
        confidence = plan.get("confidence")
        if (
            not isinstance(confidence, (int, float))
            or isinstance(confidence, bool)
            or not math.isfinite(confidence)
            or confidence < 0.85
            or confidence > 1
        ):
            raise BrokerError(HTTPStatus.CONFLICT, "navigation confidence is below the routine threshold")
        utterance = plan.get("utterance")
        if not isinstance(utterance, str) or not utterance.strip() or len(utterance) > 4096:
            raise BrokerError(HTTPStatus.BAD_REQUEST, "invalid navigation utterance")
        if action == "open_url":
            url = plan.get("url")
            if not isinstance(url, str) or len(url) > 4096 or not re.match(r"^https?://", url, re.I):
                raise BrokerError(HTTPStatus.BAD_REQUEST, "open_url requires an HTTP(S) URL")
        if action == "open_shell_app" and plan.get("appId") not in ALLOWED_SHELL_APPS:
            raise BrokerError(HTTPStatus.BAD_REQUEST, "unknown shell application")
        if action == "search":
            query = plan.get("query")
            if not isinstance(query, str) or not query.strip() or len(query) > 2048:
                raise BrokerError(HTTPStatus.BAD_REQUEST, "search requires a bounded query")
        if action == "close_window":
            target = plan.get("target")
            if not isinstance(target, dict) or not isinstance(target.get("windowId"), str):
                raise BrokerError(HTTPStatus.BAD_REQUEST, "close_window requires a concrete window")
        return plan

    def _expire(self) -> None:
        now = time.monotonic()
        expired = [token for token, item in self.pending.items() if now - item.issued_monotonic > self.permit_ttl_seconds]
        for token in expired:
            self.pending.pop(token, None)

    def authorize(self, plan_value: Any, context_value: Any) -> dict[str, Any]:
        plan = self.validate_plan(plan_value)
        if not isinstance(context_value, dict):
            raise BrokerError(HTTPStatus.BAD_REQUEST, "desktop context must be an object")
        plan_digest = sha256(canonical(plan)).hexdigest()
        permit = secrets.token_urlsafe(32)
        evidence_ref = self.ledger.append(
            "authorized",
            {
                "plan_id": plan["planId"],
                "action": plan["action"],
                "plan_digest": plan_digest,
            },
        )
        with self.lock:
            self._expire()
            self.pending[permit] = PendingPermit(plan["planId"], plan_digest, time.monotonic())
        return {
            "ok": True,
            "plan": plan,
            "permit": permit,
            "planDigest": plan_digest,
            "evidenceRef": evidence_ref,
            "message": "Routine desktop action authorized.",
        }

    def complete(self, plan_id: Any, permit: Any, message: Any) -> dict[str, Any]:
        if not isinstance(plan_id, str) or not PLAN_ID.fullmatch(plan_id):
            raise BrokerError(HTTPStatus.BAD_REQUEST, "invalid plan identifier")
        if not isinstance(permit, str) or len(permit) > 256:
            raise BrokerError(HTTPStatus.BAD_REQUEST, "invalid action permit")
        if not isinstance(message, str) or len(message) > 4096:
            raise BrokerError(HTTPStatus.BAD_REQUEST, "invalid completion message")
        with self.lock:
            self._expire()
            pending = self.pending.get(permit)
            if pending is None or not secrets.compare_digest(pending.plan_id, plan_id):
                raise BrokerError(HTTPStatus.CONFLICT, "permit is expired, unknown, or already consumed")
            evidence_ref = self.ledger.append(
                "completed",
                {
                    "plan_id": plan_id,
                    "plan_digest": pending.plan_digest,
                    "result_digest": sha256(message.encode()).hexdigest(),
                    "outcome": "succeeded",
                },
            )
            self.pending.pop(permit, None)
        return {
            "ok": True,
            "planId": plan_id,
            "evidenceRef": evidence_ref,
            "message": "Desktop action completion recorded.",
        }


class BrokerHandler(BaseHTTPRequestHandler):
    server_version = "ARKDesktopBroker/0.1"

    @property
    def state(self) -> BrokerState:
        return self.server.state  # type: ignore[attr-defined]

    def _json(self, status: int, body: dict[str, Any]) -> None:
        encoded = canonical(body)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(encoded)

    def _body(self) -> Any:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as error:
            raise BrokerError(HTTPStatus.BAD_REQUEST, "invalid content length") from error
        if length < 1 or length > 65536:
            raise BrokerError(HTTPStatus.BAD_REQUEST, "request body must be 1 to 65,536 bytes")
        try:
            return json.loads(self.rfile.read(length))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise BrokerError(HTTPStatus.BAD_REQUEST, "request body must be valid JSON") from error

    def do_GET(self) -> None:  # noqa: N802
        if self.path != "/health":
            self._json(HTTPStatus.NOT_FOUND, {"ok": False, "message": "not found"})
            return
        with self.state.lock:
            self.state._expire()
            pending_count = len(self.state.pending)
        self._json(
            HTTPStatus.OK,
            {
                "ok": True,
                "component": "ark-ui-broker",
                "critical": True,
                "ledgerSequence": self.state.ledger.sequence,
                "ledgerTip": self.state.ledger.tip,
                "pendingPermits": pending_count,
            },
        )

    def do_POST(self) -> None:  # noqa: N802
        try:
            body = self._body()
            if not isinstance(body, dict):
                raise BrokerError(HTTPStatus.BAD_REQUEST, "request body must be an object")
            if self.path == "/v1/actions":
                result = self.state.authorize(body.get("plan"), body.get("context", {}))
            elif self.path == "/v1/actions/complete":
                result = self.state.complete(body.get("planId"), body.get("permit"), body.get("message"))
            else:
                raise BrokerError(HTTPStatus.NOT_FOUND, "not found")
            self._json(HTTPStatus.OK, result)
        except BrokerError as error:
            self._json(error.status, {"ok": False, "message": str(error)})
        except Exception:
            self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"ok": False, "message": "desktop broker internal failure"})

    def log_message(self, format: str, *args: Any) -> None:
        return


class BrokerServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], state: BrokerState) -> None:
        super().__init__(address, BrokerHandler)
        self.state = state


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18082)
    parser.add_argument("--ledger", type=Path, default=Path("/var/log/ark/desktop-actions.jsonl"))
    args = parser.parse_args()
    if args.host not in {"127.0.0.1", "::1", "localhost"}:
        parser.error("the desktop broker must bind to loopback")
    state = BrokerState(EvidenceLedger(args.ledger))
    server = BrokerServer((args.host, args.port), state)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
