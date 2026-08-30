#!/usr/bin/env python3
from __future__ import annotations
import json, os, socket, subprocess, urllib.request
from datetime import datetime, timezone
from pathlib import Path

SOCKET = Path('/run/ark-display/state.sock')
STATUS = 'http://127.0.0.1:8081'
UNITS = ('ark.target','ark-kj.service','ark-agent@kyle.service','ark-agent@aletheia.service','ark-agent@joey.service','ark-agent@hrm.service','ark-agent@kenny.service','arkd.service','ark-local-api.service','ark-trading.service','NetworkManager.service','nftables.service')

def http_json(path):
    req=urllib.request.Request(STATUS+path,headers={'Accept':'application/json'})
    with urllib.request.urlopen(req,timeout=2) as r:
        v=json.loads(r.read().decode())
    return v if isinstance(v,dict) else {}

def unit_state(unit):
    try:
        r=subprocess.run(['systemctl','is-active',unit],text=True,capture_output=True,timeout=2)
        return (r.stdout.strip() or 'inactive')[:64]
    except Exception:
        return 'unknown'

def snapshot():
    try:
        s=http_json('/status'); h=s.get('health') or {}; o=(s.get('outcomes') or {}).get('last_outcome') or {}
        runtime={'available':True,'ready':bool(h.get('ready',h.get('alive',False))),'outcome':{k:o.get(k) for k in ('classification','evidence_level','blocker_demonstrated','user_action_required','user_action','summary')}}
    except Exception as exc:
        runtime={'available':False,'ready':False,'outcome':{'classification':'unknown_internal','evidence_level':'observed','blocker_demonstrated':True,'user_action_required':False,'user_action':'','summary':f'status unavailable: {type(exc).__name__}: {exc}'}}
    return {'ok':True,'adapter':'ark-display-adapter','read_only':True,'authority':'none','generated_at_utc':datetime.now(timezone.utc).isoformat(),'runtime':runtime,'system':{'services':{u:unit_state(u) for u in UNITS}}}

def serve():
    SOCKET.parent.mkdir(parents=True,exist_ok=True); SOCKET.unlink(missing_ok=True)
    srv=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); srv.bind(str(SOCKET)); os.chmod(SOCKET,0o666); srv.listen(16)
    try:
        while True:
            c,_=srv.accept()
            with c:
                c.settimeout(5); data=b''
                try:
                    while b'\n' not in data and len(data)<16384:
                        part=c.recv(4096)
                        if not part: break
                        data+=part
                    req=json.loads((data.split(b'\n',1)[0] or b'{}').decode()); op=str(req.get('op') or 'snapshot')
                    out=snapshot() if op=='snapshot' else ({'ok':True,'adapter':'ark-display-adapter'} if op=='ping' else {'ok':False,'error':'unsupported_operation'})
                except Exception as exc: out={'ok':False,'error':type(exc).__name__,'detail':str(exc)}
                c.sendall(json.dumps(out,sort_keys=True,separators=(',',':')).encode()+b'\n')
    finally:
        srv.close(); SOCKET.unlink(missing_ok=True)
if __name__=='__main__': serve()
