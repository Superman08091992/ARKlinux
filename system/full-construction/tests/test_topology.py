#!/usr/bin/env python3
from pathlib import Path
import csv
R=Path(__file__).resolve().parents[1]
def rows(name, fields):
 out=[]
 for line in (R/name).read_text().splitlines():
  if not line.strip() or line.lstrip().startswith('#'): continue
  p=line.split('\t'); assert len(p)==fields,(name,line,len(p)); out.append(p)
 return out
s=rows('config/subvolumes.tsv',7); p=rows('config/processes.tsv',6)
subs=[x[0] for x in s]; mps=[x[1] for x in s]
assert len(subs)==len(set(subs)), 'duplicate subvolume'
assert len(mps)==len(set(mps)), 'duplicate mountpoint'
required_os={'@','@home','@root','@var','@log','@pkg','@swap','@snapshots'}
assert required_os <= set(subs)
required_ark={'@ark-runtime','@ark-systems','@ark-bus','@ark-ingestion','@ark-quarantine','@ark-kyle','@ark-joey','@ark-hrm','@ark-kenny','@ark-watchdog','@ark-models','@ark-vault','@ark-apps','@ark-storage','@ark-backups','@ark-artifacts','@ark-checkpoints','@ark-archives','@ark-scratch','@ark-datasets'}
assert required_ark <= set(subs)
for bad in ('concipere','realiser','actuare','reconnoistre','recolligere','suus-affermen','cubes'):
 assert all(bad not in x.lower() for x in subs+mps), f'rejected semantic path present: {bad}'
roles={x[1] for x in p}
assert {'arkd','bus','watchdog','kyle','joey','hrm','kenny','ingest','model-router','hardwared'} <= roles
# Aletheia storage must be reserved, not implemented as a running process here.
assert any(x[6]=='aletheia-reserved' for x in s)
assert 'aletheia' not in roles
print(f'{len(s)} subvolumes; {len(p)} native process definitions: PASS')
