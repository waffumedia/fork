#!/Users/waffu/Claude/tools/asr/.venv-mlx/bin/python
"""Tag every scene of ready sources with Qwen3-VL (local, MLX) using pipeline/taxonomy.json.

usage: ~/Claude/tools/asr/.venv-mlx/bin/python pipeline/tag.py [--only ID,ID] [--force]

Loads the model once, then one call per source with that source's scene screenshots.
Writes title / description / tags / concepts onto each scene in data/sources/<id>.json
and sets status 'tagged'.
"""
import argparse, json, pathlib, re, sys, tempfile, time, subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASR = pathlib.Path.home() / 'Claude/tools/asr'
sys.path.insert(0, str(ASR))
import stack  # noqa: E402  (sets HF env, gives gpu_lock)

TAX = json.loads((ROOT / 'pipeline/taxonomy.json').read_text())
FACETS = [k for k in TAX if not k.startswith('_')]
MAX_IMGS = 18

PROMPT = """You are a motion-design and video-editing curator. The {n} images are screenshots of scenes from ONE {kind} ("{title}" by @{author}).
Image k is scene k (0-based). For EVERY scene return one JSON object. Use ONLY these vocabularies for the tag fields:
{vocab}
Return ONLY a JSON array, no prose, like:
[{{"scene":0,"title":"<=6 words naming what is on screen","description":"one sentence: what is shown and what makes it visually interesting / how it was likely made","technique":[...],"style":[...],"format":[...],"motion":[...],"medium":[...],"palette":[...],"concepts":["2-4 short lowercase free ideas, e.g. 'product on pedestal', 'type as texture'"],"quality":1-5}}]
quality = how strong this frame is as a design reference (5 = portfolio-grade). Pick 1-4 tags per facet; guess medium/motion from the look."""


def vocab_text():
    return '\n'.join(f'- {k}: ' + ', '.join(TAX[k]) for k in FACETS)


def hero(scene):
    f = scene['frames']; return f[len(f) // 2]


def small(path, tmp, i):
    p = tmp / f'{i:02}.jpg'
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(path), '-vf',
                    "scale='if(gt(iw,ih),min(672,iw),-2)':'if(gt(iw,ih),-2,min(672,ih))'", '-q:v', '3', str(p)], check=True)
    return str(p)


def parse(text):
    """Whole array if valid, else every decodable {...} object (survives truncated / looping output)."""
    m = re.search(r'\[.*\]', text, re.S)
    if m:
        for cand in (m.group(0), re.sub(r',\s*([\]}])', r'\1', m.group(0))):
            try:
                v = json.loads(cand)
                if isinstance(v, list): return v
            except json.JSONDecodeError: pass
    dec, rows, i = json.JSONDecoder(), [], 0
    while (i := text.find('{', i)) != -1:
        try:
            obj, end = dec.raw_decode(text, i)
            if isinstance(obj, dict) and ('title' in obj or 'technique' in obj): rows.append(obj)
            i = end
        except json.JSONDecodeError: i += 1
    if not rows: raise ValueError('no JSON objects: ' + text[:200])
    return rows


def clean(row):
    out = {}
    for k in FACETS:
        allowed = set(TAX[k])
        out[k] = [t for t in dict.fromkeys(str(x).strip().lower() for x in (row.get(k) or [])) if t in allowed][:4]
    out['concepts'] = [re.sub(r'\s+', ' ', str(c).strip().lower())[:40] for c in (row.get('concepts') or [])][:4]
    out['title'] = str(row.get('title') or '').strip()[:80]
    out['description'] = str(row.get('description') or '').strip()[:400]
    try: out['quality'] = max(1, min(5, int(row.get('quality') or 3)))
    except (TypeError, ValueError): out['quality'] = 3
    return out


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--only', default=''); ap.add_argument('--force', action='store_true')
    a = ap.parse_args()
    keep = set(filter(None, a.only.split(',')))
    files = sorted((ROOT / 'data/sources').glob('*.json'))
    todo = []
    for p in files:
        s = json.loads(p.read_text())
        if keep and s['id'] not in keep: continue
        if s.get('status') == 'ready' or (a.force and s.get('status') == 'tagged'): todo.append(p)
    print(json.dumps({'todo': len(todo)}), flush=True)
    if not todo: return
    from mlx_vlm import load, generate, apply_chat_template
    with stack.gpu_lock():
        model, proc = load(stack.VL)
        for p in todo:
            s = json.loads(p.read_text()); t0 = time.time()
            scenes = s['scenes']
            try:
                for start in range(0, len(scenes), MAX_IMGS):
                    chunk = scenes[start:start + MAX_IMGS]
                    tmp = pathlib.Path(tempfile.mkdtemp())
                    imgs = [small(ROOT / 'data' / hero(sc), tmp, i) for i, sc in enumerate(chunk)]
                    q = PROMPT.format(n=len(imgs), kind='video' if any(sc['kind'] == 'video' for sc in chunk) else 'image post',
                                      title=(s.get('title') or '')[:100].replace('"', "'"), author=s.get('author') or '?', vocab=vocab_text())
                    prompt = apply_chat_template(proc, model.config, q, num_images=len(imgs))
                    r = generate(model, proc, prompt, imgs, max_tokens=320 * len(imgs) + 200, temperature=0.2, repetition_penalty=1.05, verbose=False)
                    rows = parse(r.text)
                    by = {int(x.get('scene', i)): x for i, x in enumerate(rows) if isinstance(x, dict)}
                    for i, sc in enumerate(chunk):
                        if i in by: sc['tags'] = clean(by[i])
                missing = sum(1 for sc in scenes if 'tags' not in sc)
                s['status'] = 'tagged' if missing == 0 else 'ready'
                s['tag_model'] = stack.VL
                if missing: s['tag_error'] = f'{missing} scenes untagged'
                else: s.pop('tag_error', None)
            except Exception as e:
                s['tag_error'] = f'{type(e).__name__}: {e}'[:300]
            p.write_text(json.dumps(s, indent=2))
            print(json.dumps({'id': s['id'], 'status': s['status'], 'scenes': len(scenes), 'sec': round(time.time() - t0, 1), 'err': s.get('tag_error')}), flush=True)
        del model, proc; stack.free()


if __name__ == '__main__':
    main()
