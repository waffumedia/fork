#!/usr/bin/env python3
"""Ingest links into Fork: download -> scene split -> screenshots -> data/sources/<id>.json

usage: python3 pipeline/ingest.py seed/links.txt [--only ID,ID] [--force] [--jobs 3]
       python3 pipeline/ingest.py --url https://x.com/a/status/1

Per link it writes data/sources/<id>.json (the source record, agent-readable) and
data/media/<id>/s<NN>_<k>.jpg (scene screenshots). Creator profiles and websites are
recorded as `seed` sources (no download). Re-running skips finished sources.
"""
import argparse, concurrent.futures as cf, json, pathlib, re, subprocess, sys, time, urllib.parse, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / 'data'
YTDLP = '/opt/homebrew/bin/yt-dlp'
UA = 'fork-ingest/0.1'


# ---------- url handling ----------
def classify(url: str) -> dict:
    url = url.strip()
    u = urllib.parse.urlparse(url)
    host = u.netloc.lower().removeprefix('www.').removeprefix('m.')
    if host in ('youtube.com', 'youtu.be'):
        vid = urllib.parse.parse_qs(u.query).get('v', [None])[0] if host == 'youtube.com' else u.path.strip('/')
        if not vid and '/shorts/' in u.path: vid = u.path.split('/shorts/')[1].split('/')[0]
        if vid: return {'id': f'yt-{vid}', 'platform': 'youtube', 'kind': 'video', 'url': f'https://www.youtube.com/watch?v={vid}', 'native_id': vid}
    if host in ('x.com', 'twitter.com', 'fxtwitter.com', 'vxtwitter.com'):
        m = re.match(r'^/([^/]+)/status/(\d+)', u.path)
        if m: return {'id': f'x-{m.group(2)}', 'platform': 'x', 'kind': 'post', 'url': f'https://x.com/{m.group(1)}/status/{m.group(2)}', 'native_id': m.group(2), 'author': m.group(1)}
        handle = u.path.strip('/').split('/')[0]
        if handle: return {'id': f'creator-x-{handle.lower()}', 'platform': 'x', 'kind': 'creator', 'url': f'https://x.com/{handle}', 'author': handle}
    if host in ('instagram.com',):
        m = re.match(r'^/(?:p|reel|reels)/([^/]+)', u.path)
        if m: return {'id': f'ig-{m.group(1)}', 'platform': 'instagram', 'kind': 'post', 'url': f'https://www.instagram.com/reel/{m.group(1)}/', 'native_id': m.group(1)}
    if host in ('pinterest.com', 'pin.it') or host.endswith('.pinterest.com'):
        m = re.search(r'/pin/(\d+)', u.path)
        if m: return {'id': f'pin-{m.group(1)}', 'platform': 'pinterest', 'kind': 'post', 'url': f'https://www.pinterest.com/pin/{m.group(1)}/', 'native_id': m.group(1)}
    slug = re.sub(r'[^a-z0-9]+', '-', (host + u.path).lower()).strip('-')[:60]
    return {'id': f'site-{slug}', 'platform': 'web', 'kind': 'creator', 'url': url}


def deep_link(src: dict, t: float) -> str:
    """Link that opens the source at time t where the platform supports it."""
    if src['platform'] == 'youtube': return f"https://www.youtube.com/watch?v={src['native_id']}&t={int(t)}s"
    return src['url']


def fmt_ts(t: float) -> str:
    t = int(round(t)); h, m, s = t // 3600, t % 3600 // 60, t % 60
    return f'{h}:{m:02}:{s:02}' if h else f'{m}:{s:02}'


# ---------- helpers ----------
def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def fetch_json(url):
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=30) as r: return json.load(r)


def download(url, dest):
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=120) as r, open(dest, 'wb') as f:
        while chunk := r.read(1 << 20): f.write(chunk)


def probe(path):
    r = run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height:format=duration', '-of', 'json', str(path)])
    d = json.loads(r.stdout or '{}'); st = (d.get('streams') or [{}])[0]
    return float(d.get('format', {}).get('duration') or 0), st.get('width'), st.get('height')


# ---------- fetch per platform ----------
def fetch_x(src, raw):
    d = fetch_json(f"https://api.fxtwitter.com/status/{src['native_id']}")['tweet']
    src.update(title=(d.get('text') or '').split('\n')[0][:140], text=d.get('text') or '',
               author=d.get('author', {}).get('screen_name') or src.get('author'),
               author_name=d.get('author', {}).get('name'), posted_at=d.get('created_at'),
               likes=d.get('likes'), views=d.get('views'))
    media = (d.get('media') or {}).get('all') or []
    # quote tweets often carry the media
    if not media and d.get('quote'): media = (d['quote'].get('media') or {}).get('all') or []
    files = []
    for i, m in enumerate(media):
        if m['type'] in ('video', 'gif'):
            p = raw / f'{src["id"]}_{i}.mp4'
            if not p.exists(): download(m['url'], p)
            files.append(('video', p))
        elif m['type'] == 'photo':
            p = raw / f'{src["id"]}_{i}.jpg'
            if not p.exists(): download(m['url'] + ('?name=orig' if 'pbs.twimg' in m['url'] and '?' not in m['url'] else ''), p)
            files.append(('photo', p))
    return files


def fetch_ytdlp(src, raw):
    out = raw / f'{src["id"]}.%(ext)s'
    r = run([YTDLP, '--js-runtimes', 'node', '--no-playlist', '-f', 'bv*[height<=1080][ext=mp4]+ba[ext=m4a]/b[height<=1080]/b',
             '--merge-output-format', 'mp4', '--write-info-json', '--no-progress', '-o', str(out), src['url']], timeout=1800)
    info_p = raw / f'{src["id"]}.info.json'
    if info_p.exists():
        info = json.loads(info_p.read_text())
        src.update(title=info.get('title'), author=info.get('uploader') or info.get('channel'),
                   posted_at=info.get('upload_date'), views=info.get('view_count'), text=(info.get('description') or '')[:2000])
    vids = sorted(p for p in raw.glob(f'{src["id"]}.*') if p.suffix in ('.mp4', '.webm', '.mkv'))
    if not vids: raise RuntimeError('yt-dlp: ' + (r.stderr.strip().splitlines() or ['no file'])[-1][:300])
    return [('video', vids[0])]


# ---------- scenes ----------
def cut_times(path, thresh):
    r = run(['ffmpeg', '-hide_banner', '-i', str(path), '-vf', f"scale=320:-2,select='gt(scene,{thresh})',showinfo", '-an', '-f', 'null', '-'], timeout=3600)
    return [float(m) for m in re.findall(r'pts_time:([0-9.]+)', r.stderr)]


def pick_scenes(dur, cuts, min_len=0.6):
    """Turn cut points into shots, merge tiny shots, keep a representative spread."""
    edges = [0.0] + [c for c in cuts if 0 < c < dur] + [dur]
    shots = []
    for a, b in zip(edges, edges[1:]):
        if shots and (b - a) < min_len: shots[-1][1] = b      # merge flash frames into previous shot
        elif b - a > 0.05: shots.append([a, b])
    if len(shots) > 1 and shots[0][1] - shots[0][0] < min_len: shots[1][0] = shots[0][0]; shots.pop(0)
    cap = 6 if dur <= 20 else 10 if dur <= 90 else 14 if dur <= 600 else 18
    if len(shots) <= cap: return shots, len(edges) - 1
    # one shot per equal bucket of the timeline, longest shot in each bucket wins
    picked = []
    for i in range(cap):
        lo, hi = dur * i / cap, dur * (i + 1) / cap
        cand = [s for s in shots if lo <= (s[0] + s[1]) / 2 < hi and s not in picked]
        if cand: picked.append(max(cand, key=lambda s: s[1] - s[0]))
    return picked, len(edges) - 1


def grab(path, t, dest):
    run(['ffmpeg', '-v', 'error', '-y', '-ss', f'{t:.3f}', '-i', str(path), '-frames:v', '1',
         '-vf', "scale='if(gt(iw,ih),min(1280,iw),-2)':'if(gt(iw,ih),-2,min(1280,ih))'", '-q:v', '3', str(dest)])
    return dest.exists()


def scenes_for(src, files, media_dir, thresh):
    scenes, n = [], 0
    for fi, (kind, path) in enumerate(files):
        if kind == 'photo':
            dest = media_dir / f's{n:02}_0.jpg'
            run(['ffmpeg', '-v', 'error', '-y', '-i', str(path), '-vf', "scale='min(1600,iw)':-2", '-q:v', '3', str(dest)])
            scenes.append({'idx': n, 'file': fi, 'kind': 'image', 't_start': None, 't_end': None, 'timestamp': None,
                           'frames': [f'media/{src["id"]}/{dest.name}'], 'link': src['url']}); n += 1
            continue
        dur, w, h = probe(path)
        if not dur: continue
        src.setdefault('videos', []).append({'file': fi, 'duration': round(dur, 2), 'width': w, 'height': h})
        shots, total_cuts = pick_scenes(dur, cut_times(path, thresh))
        src['shot_count'] = src.get('shot_count', 0) + total_cuts
        for a, b in shots:
            frames = []
            ts = [a + (b - a) * f for f in ((0.5,) if b - a < 1.5 else (0.2, 0.5, 0.85))]
            for k, t in enumerate(ts):
                dest = media_dir / f's{n:02}_{k}.jpg'
                if grab(path, min(t, dur - 0.05), dest): frames.append(f'media/{src["id"]}/{dest.name}')
            if not frames: continue
            mid = (a + b) / 2
            scenes.append({'idx': n, 'file': fi, 'kind': 'video', 't_start': round(a, 2), 't_end': round(b, 2),
                           't_mid': round(mid, 2), 'timestamp': fmt_ts(a), 'frames': frames, 'link': deep_link(src, a)})
            n += 1
    return scenes


# ---------- main ----------
def ingest(url, force=False, thresh=0.32):
    src = classify(url)
    out = DATA / 'sources' / f'{src["id"]}.json'
    if out.exists() and not force:
        old = json.loads(out.read_text())
        if old.get('status') in ('ready', 'tagged', 'seed'): return old
    src['input_url'] = url.strip()
    src['added_at'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    if src['kind'] == 'creator':
        src['status'] = 'seed'; src['scenes'] = []
        out.write_text(json.dumps(src, indent=2)); return src
    raw = DATA / 'raw'; media_dir = DATA / 'media' / src['id']; media_dir.mkdir(parents=True, exist_ok=True)
    try:
        files = fetch_x(src, raw) if src['platform'] == 'x' else fetch_ytdlp(src, raw)
        if not files and src['platform'] == 'x':
            files = fetch_ytdlp(src, raw)
        src['scenes'] = scenes_for(src, files, media_dir, thresh)
        src['status'] = 'ready' if src['scenes'] else 'error'
        if not src['scenes']: src['error'] = 'no media found'
    except Exception as e:  # keep going; record the failure for a retry pass
        src['status'] = 'error'; src['error'] = f'{type(e).__name__}: {e}'[:400]; src.setdefault('scenes', [])
    out.write_text(json.dumps(src, indent=2))
    return src


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('file', nargs='?'); ap.add_argument('--url'); ap.add_argument('--only', default='')
    ap.add_argument('--force', action='store_true'); ap.add_argument('--jobs', type=int, default=3)
    a = ap.parse_args()
    urls = [a.url] if a.url else [l.strip() for l in open(a.file) if l.strip() and not l.startswith('#')]
    if a.only:
        keep = set(a.only.split(',')); urls = [u for u in urls if classify(u)['id'] in keep]
    seen, todo = set(), []
    for u in urls:
        i = classify(u)['id']
        if i not in seen: seen.add(i); todo.append(u)
    with cf.ThreadPoolExecutor(a.jobs) as ex:
        for s in ex.map(lambda u: ingest(u, a.force), todo):
            print(json.dumps({'id': s['id'], 'status': s['status'], 'scenes': len(s.get('scenes', [])), 'error': s.get('error')}), flush=True)


if __name__ == '__main__':
    main()
