#!/usr/bin/env python3
"""Inspo Mac worker: download + scene-split + tag every queued link (Grokbot picks, manual adds), then import.

  python3 pipeline/worker.py          one pass
  python3 pipeline/worker.py --loop   every 10 minutes

Grokbot itself posts links to /api/grok/inbox; this only turns queued links into scenes.
Reads INSPO_URL (default http://localhost:3300) and INSPO_TOKEN from .env.local.
"""
import json, os, pathlib, subprocess, sys, time, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
for line in (ROOT / '.env.local').read_text().splitlines():
    if '=' in line and not line.startswith('#'):
        k, v = line.split('=', 1); os.environ.setdefault(k.strip(), v.strip())
BASE = os.environ.get('INSPO_URL', 'http://localhost:3300').rstrip('/')
TOKEN = os.environ['INSPO_TOKEN']
VLM_PY = str(pathlib.Path.home() / 'Claude/tools/asr/.venv-mlx/bin/python')


def api(path, body=None):
    req = urllib.request.Request(BASE + path, data=None if body is None else json.dumps(body).encode(),
                                 headers={'Content-Type': 'application/json', 'Authorization': f'Bearer {TOKEN}'},
                                 method='GET' if body is None else 'POST')
    with urllib.request.urlopen(req, timeout=300) as r: return json.load(r)


def process():
    queued = api('/api/worker')['queued']
    if not queued: print(json.dumps({'process': 0}), flush=True); return
    lst = ROOT / 'data' / 'queue.txt'
    lst.write_text('\n'.join(q['url'] for q in queued) + '\n')
    subprocess.run([sys.executable, str(ROOT / 'pipeline/ingest.py'), str(lst), '--jobs', '3'], check=False)
    ids = [q['id'] for q in queued]
    subprocess.run([VLM_PY, str(ROOT / 'pipeline/tag.py'), '--only', ','.join(ids)], check=False)
    print(json.dumps({'process': len(ids), 'import': api('/api/worker', {'ids': ids})}), flush=True)


if __name__ == '__main__':
    while True:
        try: process()
        except Exception as e: print(json.dumps({'error': str(e)}), flush=True)
        if '--loop' not in sys.argv: break
        time.sleep(600)
