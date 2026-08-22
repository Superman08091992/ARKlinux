#!/usr/bin/env python3
import argparse, ctypes, glob, grp, json, os, pwd, selectors, signal, socket, sys, time
from pathlib import Path
RUN=Path('/run/ark'); PROCS=RUN/'processes'
STOP=False
ROLE_GROUP={
 'arkd':'ark-core','bus':'ark-ipc','watchdog':'ark-watchdog','kyle':'ark-lifecycle',
 'joey':'ark-cognition','hrm':'ark-correspondence','kenny':'ark-effect','ingest':'ark-ingest',
 'model-router':'ark-model','hardwared':'ark-io'}
REQUIRED=['bus','kyle','joey','hrm','kenny','ingest','model-router','hardwared']

def stop(*_):
 global STOP; STOP=True

def set_name(name):
 try: ctypes.CDLL(None).prctl(15, name.encode()[:15], 0,0,0)
 except Exception: pass

def atomic_json(path,obj):
 path.parent.mkdir(parents=True,exist_ok=True)
 tmp=path.with_suffix(path.suffix+'.tmp')
 tmp.write_text(json.dumps(obj,sort_keys=True,separators=(',',':'))+'\n')
 os.replace(tmp,path)

def beat(role,state='ready',extra=None):
 d={'role':role,'group':ROLE_GROUP.get(role,'ark-core'),'pid':os.getpid(),'uid':os.getuid(),'gid':os.getgid(),
    'monotonic_ns':time.monotonic_ns(),'state':state}
 if extra: d.update(extra)
 atomic_json(PROCS/f'{role}.json',d)

def generic(role):
 while not STOP:
  beat(role); time.sleep(1)

def hardwared():
 while not STOP:
  hw={
   'net':[Path(x).name for x in glob.glob('/sys/class/net/*')],
   'drm':[Path(x).name for x in glob.glob('/sys/class/drm/*')],
   'sound':[Path(x).name for x in glob.glob('/sys/class/sound/*')],
   'block':[Path(x).name for x in glob.glob('/sys/class/block/*')],
   'gpio':[Path(x).name for x in glob.glob('/dev/gpiochip*')],
   'i2c':[Path(x).name for x in glob.glob('/dev/i2c-*')],
  }
  atomic_json(RUN/'hardware.json',hw); beat('hardwared',extra={'inventory':str(RUN/'hardware.json')}); time.sleep(5)

def bus():
 p=RUN/'bus.sock'
 try: p.unlink()
 except FileNotFoundError: pass
 s=socket.socket(socket.AF_UNIX,socket.SOCK_DGRAM); s.bind(str(p)); os.chmod(p,0o660); s.settimeout(1)
 while not STOP:
  beat('bus')
  try:
   data,_=s.recvfrom(65535)
   try: obj=json.loads(data.decode())
   except Exception: obj={'raw':data.decode(errors='replace')}
   atomic_json(RUN/'bus.last.json',{'received_monotonic_ns':time.monotonic_ns(),'message':obj})
  except socket.timeout: pass
 s.close(); p.unlink(missing_ok=True)

def arkd():
 while not STOP:
  now=time.monotonic_ns(); states={}; missing=[]
  for role in REQUIRED:
   p=PROCS/f'{role}.json'
   try:
    d=json.loads(p.read_text()); age=(now-int(d['monotonic_ns']))/1e9; states[role]={'age_s':round(age,3),'state':d.get('state')}
    if age>5: missing.append(role)
   except Exception: missing.append(role)
  atomic_json(RUN/'state.json',{'coordinated_process_set':'A.R.K.','state':'ready' if not missing else 'degraded','missing_or_stale':missing,'processes':states})
  beat('arkd',state='ready' if not missing else 'degraded'); time.sleep(1)

def watchdog():
 while not STOP:
  try: state=json.loads((RUN/'state.json').read_text())
  except Exception: state={'state':'bootstrap','missing_or_stale':REQUIRED}
  beat('watchdog',state='watching',extra={'ark_state':state.get('state'),'missing':state.get('missing_or_stale',[])})
  time.sleep(2)

def main():
 ap=argparse.ArgumentParser(); ap.add_argument('--role',required=True); a=ap.parse_args(); role=a.role
 RUN.mkdir(parents=True,exist_ok=True); PROCS.mkdir(parents=True,exist_ok=True); set_name('ark-'+role)
 signal.signal(signal.SIGTERM,stop); signal.signal(signal.SIGINT,stop)
 {'bus':bus,'arkd':arkd,'watchdog':watchdog,'hardwared':hardwared}.get(role,lambda:generic(role))()
 try:(PROCS/f'{role}.json').unlink()
 except FileNotFoundError:pass
if __name__=='__main__': main()
