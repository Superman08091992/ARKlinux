#!/usr/bin/env python3
from __future__ import annotations

import json
import shlex
import socket
import sys
import time
import urllib.error
import urllib.request

ROOT_SOCKET = "/run/ark-desktop/root.sock"
RUNTIME_URL = "http://127.0.0.1:18080"

UNITS = {
    "runtime": "ark-runtime-api.service",
    "status-api": "ark-local-api.service",
    "trading": "ark-trading.service",
    "hardwared": "ark-hardwared.service",
}
RUNTIME_ROLES = (
    ("Kyle", "acquisition / interface / quarantine"),
    ("Aletheia", "verification / evidence adjudication"),
    ("Joey", "analysis / planning / comparison"),
    ("HRM", "authority / execution-readiness validation"),
    ("Kenny", "approved execution submission"),
)


def root_call(payload, timeout=30):
    data = (json.dumps(payload) + "\n").encode()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        sock.connect(ROOT_SOCKET)
        sock.sendall(data)
        buf = b""
        while b"\n" not in buf:
            chunk = sock.recv(65536)
            if not chunk:
                break
            buf += chunk
    if not buf:
        raise RuntimeError("desktop broker returned no data")
    reply = json.loads(buf.split(b"\n", 1)[0].decode())
    if not reply.get("ok"):
        raise RuntimeError(reply.get("error", "desktop broker request failed"))
    return reply.get("result")


def runtime_get(path, timeout=3):
    request = urllib.request.Request(RUNTIME_URL + path, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"canonical runtime unavailable: {exc}") from exc


def unit_state(name):
    unit = UNITS[name]
    result = root_call({"op": "unit_state", "unit": unit}, 10)
    values = {"ActiveState": "unknown", "SubState": "unknown", "MainPID": "0"}
    for line in result.get("stdout", "").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return values


def service_action(action, name):
    if name not in UNITS:
        raise ValueError(f"unknown service: {name}")
    result = root_call({"op": "service", "action": action, "unit": UNITS[name]}, 125)
    detail = result.get("stderr", "").strip() or result.get("stdout", "").strip()
    print(f"{action:<7} {name:<12} {'OK' if result.get('returncode') == 0 else 'FAIL'} {detail}")


def show_logs(name, count=30):
    if name not in UNITS:
        raise ValueError(f"unknown service: {name}")
    result = root_call({"op": "journal", "unit": UNITS[name], "count": count}, 25)
    print(result.get("stdout", "") or result.get("stderr", "") or "(no log entries)")


def hardware():
    try:
        raw = root_call({"op": "runtime_read", "path": "/run/arklinux/hardware.json"}, 5)["content"]
        print(json.dumps(json.loads(raw), indent=2, sort_keys=True))
    except Exception as exc:
        print(f"hardware inventory unavailable: {exc}")


def clear():
    print("\033[2J\033[H", end="")


def print_last_outcome(status):
    outcomes = status.get("outcomes") or {}
    print("\nLast terminal outcome:")
    if outcomes.get("available") is False:
        print("  DIAGNOSTICS:  UNAVAILABLE")
        print(f"  error:        {outcomes.get('diagnostic_error') or 'cause-reporting subsystem unavailable'}")
        print("  last cause:   NOT RELIABLY AVAILABLE")
        print("  user action:  none automatically required")
        print("  DIAGNOSIS: A.R.K. cannot currently prove the last task cause; do not infer policy, product, compute, context, or user error from missing diagnostics.")
        return
    record = outcomes.get("last_outcome")
    if not record:
        print("  none recorded")
        print("  user action:  none required")
        return
    classification = record.get("classification", "unknown")
    state = record.get("state", "unknown")
    evidence = record.get("evidence_level", "unverified")
    blocker = bool(record.get("blocker_demonstrated"))
    print(f"  result:       {classification} ({state})")
    print(f"  evidence:     {evidence}")
    print(f"  blocker:      {'DEMONSTRATED' if blocker else 'NOT DEMONSTRATED'}")
    print(f"  source:       {record.get('source', 'unknown')}")
    if record.get("provider"):
        print(f"  provider:     {record.get('provider')}")
    if record.get("intervention_layer"):
        print(f"  intervention: {record.get('intervention_layer')}")
    if record.get("summary"):
        print(f"  summary:      {record.get('summary')}")
    if record.get("detail"):
        print(f"  detail:       {record.get('detail')}")
    if record.get("diagnostic_persisted") is False:
        print(f"  persistence:  FAILED ({record.get('diagnostic_error') or 'unknown persistence error'})")
    elif record.get("diagnostic_persisted") is True:
        print("  persistence:  durable")
    if record.get("user_action_required"):
        print(f"  USER ACTION:  {record.get('user_action') or 'required; reason not supplied'}")
    else:
        print("  user action:  none required")
    if classification == "premature_stop":
        print("  DIAGNOSIS: system stopped early with no demonstrated technical blocker.")
    elif classification == "unknown_internal":
        print("  DIAGNOSIS: cause is not established; do not attribute it to the user, policy, product limits, or compute without evidence.")
    elif evidence == "provider_reported":
        print("  DIAGNOSIS: provider-reported cause; A.R.K. did not independently measure it.")


def dashboard():
    print("A.R.K. OPERATOR CONSOLE")
    print("canonical runtime state • explicit execution/outcome provenance")
    print("=" * 78)

    try:
        health = runtime_get("/health")
        status = runtime_get("/status")
        runtime_ok = bool(health.get("ok"))
        authority = status.get("authority") or {}
        runtime_root = status.get("runtime_root", "unknown")
        outcomes = status.get("outcomes") or {}
        print(f"Runtime: {'READY' if runtime_ok else 'DEGRADED'}  root={runtime_root}")
        print(
            "Authority: mode={}  real-tools={}  AEM={}".format(
                authority.get("mode", "unknown"),
                authority.get("broker_executes_real_tools", "unknown"),
                authority.get("aem_role", "unknown"),
            )
        )
        diagnostic_state = "AVAILABLE" if outcomes.get("available", True) else "UNAVAILABLE"
        print(
            "Evidence: {} records   Bus: {} events   Outcomes: {} / {} records / chain={}".format(
                (status.get("evidence") or {}).get("record_count", "?"),
                (status.get("bus") or {}).get("event_count", "?"),
                diagnostic_state,
                outcomes.get("record_count", "?"),
                "VALID" if outcomes.get("chain_valid") else "INVALID/UNKNOWN",
            )
        )
        print_last_outcome(status)
    except Exception as exc:
        print(f"Runtime: UNAVAILABLE ({exc})")
        print("Last terminal outcome: unavailable because runtime status could not be read; cause not inferred.")

    print("\nRuntime roles (logical stages, not fake per-agent daemons):")
    for name, role in RUNTIME_ROLES:
        print(f"  {name:<10} {role}")

    print("\nServices:")
    for name in UNITS:
        try:
            state = unit_state(name)
            print(f"  {name:<12} {state['ActiveState']:<10} {state['SubState']:<12} pid={state['MainPID']}")
        except Exception as exc:
            print(f"  {name:<12} unavailable ({exc})")

    print("\nCommands: status | outcomes | contract | events [N] | services | start NAME | stop NAME")
    print("          restart NAME | logs NAME [N] | hardware | watch | help | exit")


def show_contract():
    print(json.dumps(runtime_get("/contract"), indent=2, sort_keys=True))


def show_outcomes():
    status = runtime_get("/status")
    print(json.dumps(status.get("outcomes") or {}, indent=2, sort_keys=True))


def show_events(count=20):
    payload = runtime_get("/bus/events", timeout=5)
    events = list(payload.get("events") or [])[-max(1, min(int(count), 200)):]
    print(json.dumps(events, indent=2, sort_keys=True))


def services():
    for name in UNITS:
        try:
            state = unit_state(name)
            print(f"{name:<12} {state['ActiveState']:<10} {state['SubState']:<12} pid={state['MainPID']}")
        except Exception as exc:
            print(f"{name:<12} ERROR {exc}")


def help_text():
    print("""A.R.K. operator console

status                  canonical runtime + outcome + service summary
outcomes                show complete terminal-outcome diagnostic state
contract                show runtime API contract
events [N]              show last N append-only runtime bus events
services                show systemd state for real runtime/substrate services
start NAME              start a service
stop NAME               stop a service
restart NAME            restart a service
logs NAME [N]           show service journal
hardware                show ARKlinux hardware inventory
watch                   refresh status every 2 seconds
help                    show this help
exit                    close console

Outcome classes are explicit: completed, technical_limit, tool_unavailable,
context_degraded, product_limit, policy_intervention, reasoning_failure,
premature_stop, dependency_failure, input_invalid, authority_denied,
unknown_internal.

Evidence levels are separate from the outcome: observed, provider_reported,
inferred, unverified. If the platform does not expose enough telemetry to prove a
cause, A.R.K. must say unknown_internal rather than inventing one.

If outcome diagnostics themselves become unavailable, the console says so explicitly
and does not turn missing telemetry into a guessed task cause.

Service names: runtime, status-api, trading, hardwared

Trading is intentionally not enabled by the image builder until a persisted
mandate and brokerage credentials are installed. The console never reports a
trade as executed unless the canonical runtime evidence says it occurred.
""")


def execute(line):
    parts = shlex.split(line)
    if not parts:
        return True
    cmd = parts[0].lower()
    if cmd in {"exit", "quit", "q"}:
        return False
    if cmd == "help":
        help_text()
    elif cmd == "status":
        dashboard()
    elif cmd == "outcomes":
        show_outcomes()
    elif cmd == "contract":
        show_contract()
    elif cmd == "events":
        show_events(int(parts[1]) if len(parts) > 1 else 20)
    elif cmd == "services":
        services()
    elif cmd in {"start", "stop", "restart"}:
        if len(parts) != 2:
            raise ValueError(f"usage: {cmd} NAME")
        service_action(cmd, parts[1])
    elif cmd == "logs":
        if len(parts) not in {2, 3}:
            raise ValueError("usage: logs NAME [N]")
        show_logs(parts[1], int(parts[2]) if len(parts) == 3 else 30)
    elif cmd == "hardware":
        hardware()
    elif cmd == "watch":
        try:
            while True:
                clear()
                dashboard()
                print("\nRefreshing every 2s. Ctrl-C returns to console.")
                time.sleep(2)
        except KeyboardInterrupt:
            print()
    else:
        raise ValueError(f"unknown command: {cmd}; type help")
    return True


def repl():
    clear()
    dashboard()
    while True:
        try:
            if not execute(input("ark> ")):
                return
        except (EOFError, KeyboardInterrupt):
            print()
            return
        except Exception as exc:
            print(f"ERROR: {exc}")


def main():
    try:
        root_call({"op": "ping"}, 3)
    except Exception as exc:
        print(f"ARKlinux desktop broker unavailable: {exc}", file=sys.stderr)
        return 1
    if len(sys.argv) == 1:
        repl()
        return 0
    try:
        execute(" ".join(shlex.quote(x) for x in sys.argv[1:]))
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
