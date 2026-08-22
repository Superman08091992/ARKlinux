#!/usr/bin/env python3
import json
import shlex
import socket
import sys
import time
from pathlib import Path

SOCKET_PATH = "/run/ark-desktop/root.sock"

UNITS = {
    "kyle": "ark-kyle.service",
    "joey": "ark-joey.service",
    "hrm": "ark-hrm.service",
    "kenny": "ark-kenny.service",
    "watchdog": "ark-watchdog.service",
    "model-router": "ark-model-router.service",
    "ingest": "ark-ingest.service",
    "hardwared": "ark-hardwared.service",
    "bus": "ark-bus.service",
    "arkd": "arkd.service",
}
AGENTS = ("kyle", "joey", "hrm", "kenny")
INFRA = tuple(name for name in UNITS if name not in AGENTS)


def root_call(payload, timeout=30):
    data = (json.dumps(payload) + "\n").encode()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        sock.connect(SOCKET_PATH)
        sock.sendall(data)
        buf = b""
        while b"\n" not in buf:
            chunk = sock.recv(65536)
            if not chunk:
                break
            buf += chunk
    if not buf:
        raise RuntimeError("root broker returned no data")
    reply = json.loads(buf.split(b"\n", 1)[0].decode())
    if not reply.get("ok"):
        raise RuntimeError(reply.get("error", "root broker request failed"))
    return reply.get("result")


def root_exec(argv, timeout=30):
    return root_call({"op": "exec", "argv": argv, "timeout": timeout}, timeout + 5)


def root_read(path):
    return root_call({"op": "read_file", "path": path}, 5)["content"]


def read_json(path):
    try:
        return json.loads(root_read(path))
    except Exception:
        return None


def unit_state(name):
    unit = UNITS[name]
    result = root_exec([
        "systemctl", "show", unit,
        "--property=ActiveState", "--property=SubState", "--property=MainPID",
        "--no-pager",
    ], 5)
    values = {"ActiveState": "unknown", "SubState": "unknown", "MainPID": "0"}
    for line in result.get("stdout", "").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return values


def heartbeat(name):
    return read_json(f"/run/ark/processes/{name}.json")


def age_seconds(hb):
    if not hb:
        return None
    try:
        now = time.clock_gettime_ns(time.CLOCK_MONOTONIC)
        return max(0.0, (now - int(hb["monotonic_ns"])) / 1_000_000_000)
    except Exception:
        return None


def short_state(name):
    st = unit_state(name)
    hb = heartbeat(name)
    age = age_seconds(hb)
    heartbeat_state = hb.get("state", "-") if hb else "missing"
    age_text = "-" if age is None else f"{age:5.1f}s"
    return st, heartbeat_state, age_text


def clear():
    print("\033[2J\033[H", end="")


def banner():
    print("A.R.K. OPERATOR CONSOLE")
    print("coordinated process controls • local root broker")
    print("=" * 72)


def dashboard():
    banner()
    state = read_json("/run/ark/state.json") or {}
    overall = str(state.get("state", "unknown")).upper()
    missing = state.get("missing_or_stale", [])
    print(f"A.R.K. state: {overall:<10}  missing/stale: {', '.join(missing) if missing else 'none'}")
    print()
    print(f"{'ROLE':<14} {'SERVICE':<10} {'PROCESS':<12} {'HEARTBEAT':>10} {'PID':>8}")
    print("-" * 72)
    for name in UNITS:
        try:
            st, hb_state, age = short_state(name)
            print(
                f"{name:<14} {st['ActiveState']:<10} {hb_state:<12} {age:>10} {st['MainPID']:>8}"
            )
        except Exception as exc:
            print(f"{name:<14} ERROR      {str(exc)[:46]}")
    print()
    print("Named agents: Kyle • Joey • HRM • Kenny")
    print("Current agent bodies are native heartbeat scaffolds; model dialogue is not wired yet.")
    print()
    print("Commands: status | state | start NAME | stop NAME | restart NAME | logs NAME [N]")
    print("          hardware | bus | agents | infra | watch | help | exit")


def names_for(token):
    token = token.lower()
    if token == "all":
        return list(UNITS)
    if token == "agents":
        return list(AGENTS)
    if token == "infra":
        return list(INFRA)
    if token not in UNITS:
        raise ValueError(f"unknown role: {token}")
    return [token]


def service_action(action, token):
    for name in names_for(token):
        result = root_call({"op": "service", "action": action, "unit": UNITS[name]}, 125)
        rc = result.get("returncode", 1)
        detail = result.get("stderr", "").strip() or result.get("stdout", "").strip()
        print(f"{action:<7} {name:<14} {'OK' if rc == 0 else 'FAIL'} {detail}")


def show_logs(name, count=30):
    names = names_for(name)
    for role in names:
        print(f"\n--- {role} / {UNITS[role]} ---")
        result = root_exec([
            "journalctl", "-u", UNITS[role], "-n", str(max(1, min(count, 500))),
            "--no-pager", "--output=short-iso",
        ], 15)
        print(result.get("stdout", "") or result.get("stderr", "") or "(no log entries)")


def show_json_file(path, title):
    print(title)
    data = read_json(path)
    if data is None:
        print("unavailable")
    else:
        print(json.dumps(data, indent=2, sort_keys=True))


def help_text():
    print("""A.R.K. terminal controls

status                  show coordinated dashboard
state                   show raw /run/ark/state.json
agents                  show Kyle/Joey/HRM/Kenny only
infra                   show support processes only
start NAME              start role; NAME may be all, agents, or infra
stop NAME               stop role; NAME may be all, agents, or infra
restart NAME            restart role; NAME may be all, agents, or infra
logs NAME [N]           last N journal lines, default 30
hardware                show hardwared inventory
bus                     show last bus message
watch                   refresh dashboard every 2 seconds (Ctrl-C to stop)
help                    show this help
exit                    close console

Roles: kyle joey hrm kenny watchdog model-router ingest hardwared bus arkd
""")


def list_subset(names):
    banner()
    for name in names:
        st, hb_state, age = short_state(name)
        print(f"{name:<14} service={st['ActiveState']:<9} process={hb_state:<12} heartbeat={age:>8} pid={st['MainPID']}")


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
    elif cmd == "state":
        show_json_file("/run/ark/state.json", "A.R.K. coordinated state")
    elif cmd == "hardware":
        show_json_file("/run/ark/hardware.json", "ARKlinux hardware inventory")
    elif cmd == "bus":
        show_json_file("/run/ark/bus.last.json", "A.R.K. last bus message")
    elif cmd == "agents":
        list_subset(AGENTS)
    elif cmd == "infra":
        list_subset(INFRA)
    elif cmd in {"start", "stop", "restart"}:
        if len(parts) != 2:
            raise ValueError(f"usage: {cmd} NAME")
        service_action(cmd, parts[1])
    elif cmd == "logs":
        if len(parts) not in {2, 3}:
            raise ValueError("usage: logs NAME [N]")
        show_logs(parts[1], int(parts[2]) if len(parts) == 3 else 30)
    elif cmd == "watch":
        try:
            while True:
                clear()
                dashboard()
                print("Refreshing every 2s. Ctrl-C returns to console.")
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
            line = input("ark> ")
            if not execute(line):
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
        print(f"ARK desktop root broker unavailable: {exc}", file=sys.stderr)
        return 1
    if len(sys.argv) == 1:
        repl()
        return 0
    command = " ".join(shlex.quote(x) for x in sys.argv[1:])
    try:
        execute(command)
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
