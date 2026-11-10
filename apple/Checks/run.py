#!/usr/bin/env python3
"""Run read-only checks against the local API without writing credentials to disk."""
import os
from pathlib import Path
import subprocess
import tempfile

apple = Path(__file__).resolve().parents[1]
env = os.environ.copy()
if not env.get('FORK_TOKEN'):
    for line in (apple.parent / '.env.local').read_text().splitlines():
        if line.startswith('FORK_TOKEN='):
            env['FORK_TOKEN'] = line.split('=', 1)[1].strip().strip('\"\'')
env.setdefault('FORK_URL', 'http://localhost:3300')
with tempfile.TemporaryDirectory(prefix='fork-check-') as temp:
    executable = Path(temp) / 'smoke'
    cache = Path.home() / 'Library/Caches/ForkSwift'
    subprocess.run([
        'xcrun', 'swiftc', '-D', 'DEBUG', '-disable-sandbox', '-swift-version', '6',
        '-module-cache-path', str(cache), '-parse-as-library',
        *[str(apple / 'Fork' / name) for name in ['Models.swift', 'APIClient.swift', 'GraphLayout.swift']],
        str(apple / 'Checks/Smoke.swift'), '-o', str(executable)
    ], check=True)
    result = subprocess.run([str(executable)], env=env, text=True, capture_output=True)
    (apple / 'smoke.log').write_text(result.stdout + result.stderr)
    print(result.stdout + result.stderr, end='')
    raise SystemExit(result.returncode)
