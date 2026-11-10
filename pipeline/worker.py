#!/usr/bin/env python3
"""Fork Mac worker: download + scene-split + tag every queued link (Grokbot picks, manual adds), then import.

  python3 pipeline/worker.py          one pass
  python3 pipeline/worker.py --loop   every 10 minutes

Grokbot itself posts links to /api/grok/inbox; this only turns queued links into scenes.
Reads FORK_URL (default http://localhost:3300) and FORK_TOKEN from .env.local.
"""
import json, os, pathlib, subprocess, sys, time, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
for line in (ROOT / '.env.local').read_text().splitlines():
    if '=' in line and not line.startswith('#'):
        k, v = line.split('=', 1); os.environ.setdefault(k.strip(), v.strip())
BASE = os.environ.get('FORK_URL', 'http://localhost:3300').rstrip('/')
TOKEN = os.environ['FORK_TOKEN']
VLM_PY = str(pathlib.Path.home() / 'Claude/tools/asr/.venv-mlx/bin/python')


def api(path, body=None):
    req = urllib.request.Request(BASE + path, data=None if body is None else json.dumps(body).encode(),
                                 headers={'Content-Type': 'application/json', 'Authorization': f'Bearer {TOKEN}'},
                                 method='GET' if body is None else 'POST')
    with urllib.request.urlopen(req, timeout=300) as r: return json.load(r)


def untagged():
    out = []
    for f in (ROOT / 'data/sources').glob('*.json'):
        try:
            if json.loads(f.read_text()).get('status') == 'ready': out.append(f.stem)
        except ValueError: pass
    return out


def process():
    """Queued links (Grokbot / app / MCP) -> download + scenes; then tag everything still untagged; then import."""
    queued = api('/api/worker')['queued']
    ids = [q['id'] for q in queued]
    if queued:
        lst = ROOT / 'data' / 'queue.txt'
        lst.write_text('\n'.join(q['url'] for q in queued) + '\n')
        subprocess.run([sys.executable, str(ROOT / 'pipeline/ingest.py'), str(lst), '--jobs', '3'], check=False)
    todo = untagged()
    if todo:
        subprocess.run([VLM_PY, str(ROOT / 'pipeline/tag.py'), '--only', ','.join(todo)], check=False)
    ids = sorted(set(ids) | set(todo))
    if not ids: print(json.dumps({'process': 0}), flush=True); return
    for i in range(0, len(ids), 40):
        print(json.dumps({'imported': api('/api/worker', {'ids': ids[i:i + 40]})}), flush=True)


if __name__ == '__main__':
    while True:
        try: process()
        except Exception as e: print(json.dumps({'error': str(e)}), flush=True)
        if '--loop' not in sys.argv: break
        time.sleep(600)
