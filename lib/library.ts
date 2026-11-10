import { promises as fs } from "node:fs";
import path from "node:path";
import { all, db, one, run } from "@/lib/db";

export const DATA_DIR = path.join(process.cwd(), "data");
export const FACETS = ["technique", "style", "format", "motion", "medium", "palette", "concepts"] as const;
export type Facet = (typeof FACETS)[number];

export type SceneTags = Partial<Record<Facet, string[]>> & { title?: string; description?: string; quality?: number };

export type Scene = {
  id: string;
  source_id: string;
  idx: number;
  kind: "video" | "image";
  t_start: number | null;
  t_end: number | null;
  timestamp: string | null;
  link: string;
  frames: string[];
  hero: string;
  title: string;
  description: string;
  quality: number | null;
  tags: SceneTags;
};

export type Source = {
  id: string;
  platform: string;
  kind: string;
  url: string;
  title: string;
  author: string;
  text: string;
  posted_at: string | null;
  added_at: string;
  origin: string;
  status: string;
  error: string | null;
  duration: number | null;
  note: string;
  pitch: string;
  verdict?: "like" | "dislike" | null;
  swiped_at?: string | null;
};

/** Public URL for a stored media path ("media/<id>/s00_1.jpg"). MEDIA_BASE_URL points at Blob storage in prod. */
export function mediaUrl(p: string, base = ""): string {
  const root = process.env.MEDIA_BASE_URL || `${base}/api`;
  return `${root.replace(/\/$/, "")}/${p}`;
}

function parseScene(r: Record<string, unknown>): Scene {
  return {
    ...(r as unknown as Scene),
    frames: JSON.parse(String(r.frames || "[]")),
    tags: JSON.parse(String(r.tags || "{}")),
  };
}

// ---------- import (pipeline JSON -> db) ----------

type SourceFile = {
  id: string; platform: string; kind: string; url: string; title?: string; author?: string; text?: string;
  posted_at?: string; added_at: string; status: string; error?: string; origin?: string; pitch?: string;
  videos?: { duration: number }[];
  scenes: {
    idx: number; kind: "video" | "image"; t_start: number | null; t_end: number | null; timestamp: string | null;
    link: string; frames: string[]; tags?: SceneTags & { title?: string; description?: string; quality?: number };
  }[];
};

export async function importSourceFile(file: string, origin?: string): Promise<string> {
  const s = JSON.parse(await fs.readFile(file, "utf8")) as SourceFile;
  await upsertSource(s, origin);
  return s.id;
}

export async function upsertSource(s: SourceFile, origin?: string) {
  const c = await db();
  const duration = s.videos?.reduce((a, v) => a + (v.duration || 0), 0) || null;
  const existing = await one<{ origin: string }>("SELECT origin FROM sources WHERE id = ?", [s.id]);
  const org = origin ?? existing?.origin ?? s.origin ?? "seed";
  const tx = await c.transaction("write");
  try {
    await tx.execute({
      sql: `INSERT INTO sources (id, platform, kind, url, title, author, text, posted_at, added_at, origin, status, error, duration, pitch)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET platform=excluded.platform, kind=excluded.kind, url=excluded.url,
              title=excluded.title, author=excluded.author, text=excluded.text, posted_at=excluded.posted_at,
              status=excluded.status, error=excluded.error, duration=excluded.duration,
              pitch=CASE WHEN excluded.pitch != '' THEN excluded.pitch ELSE sources.pitch END`,
      args: [s.id, s.platform, s.kind, s.url, s.title ?? "", s.author ?? "", s.text ?? "", s.posted_at ?? null,
        s.added_at, org, s.status, s.error ?? null, duration, s.pitch ?? ""],
    });
    await tx.execute({ sql: "DELETE FROM scenes WHERE source_id = ?", args: [s.id] });
    for (const sc of s.scenes) {
      const id = `${s.id}:${sc.idx}`;
      const t = sc.tags ?? {};
      await tx.execute({
        sql: `INSERT INTO scenes (id, source_id, idx, kind, t_start, t_end, timestamp, link, frames, hero, title, description, quality, tags)
              VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
        args: [id, s.id, sc.idx, sc.kind, sc.t_start, sc.t_end, sc.timestamp, sc.link, JSON.stringify(sc.frames),
          sc.frames[Math.floor(sc.frames.length / 2)] ?? "", t.title ?? "", t.description ?? "", t.quality ?? null,
          JSON.stringify(pickTags(t))],
      });
      for (const f of FACETS) for (const tag of t[f] ?? []) {
        await tx.execute({ sql: "INSERT OR IGNORE INTO scene_tags (scene_id, facet, tag) VALUES (?,?,?)", args: [id, f, tag] });
      }
    }
    await tx.commit();
  } catch (e) {
    await tx.rollback();
    throw e;
  }
}

function pickTags(t: SceneTags): SceneTags {
  const o: SceneTags = {};
  for (const f of FACETS) if (t[f]?.length) o[f] = t[f];
  return o;
}

export async function importAll(): Promise<{ imported: number; errors: string[] }> {
  const dir = path.join(DATA_DIR, "sources");
  const files = (await fs.readdir(dir)).filter((f) => f.endsWith(".json"));
  const errors: string[] = [];
  for (const f of files) {
    try { await importSourceFile(path.join(dir, f)); } catch (e) { errors.push(`${f}: ${(e as Error).message}`); }
  }
  return { imported: files.length - errors.length, errors };
}

// ---------- reads ----------

const SOURCE_COLS = `s.*, w.verdict AS verdict, w.at AS swiped_at`;

export async function getSource(id: string): Promise<(Source & { scenes: Scene[] }) | null> {
  const s = await one<Source>(`SELECT ${SOURCE_COLS} FROM sources s LEFT JOIN swipes w ON w.source_id = s.id WHERE s.id = ?`, [id]);
  if (!s) return null;
  const scenes = (await all("SELECT * FROM scenes WHERE source_id = ? ORDER BY idx", [id])).map(parseScene);
  return { ...s, scenes };
}

export async function getScene(id: string): Promise<(Scene & { source: Source }) | null> {
  const r = await one("SELECT * FROM scenes WHERE id = ?", [id]);
  if (!r) return null;
  const sc = parseScene(r);
  const source = await one<Source>(`SELECT ${SOURCE_COLS} FROM sources s LEFT JOIN swipes w ON w.source_id = s.id WHERE s.id = ?`, [sc.source_id]);
  return { ...sc, source: source! };
}

export async function listSources(opts: { origin?: string; status?: string; verdict?: string; limit?: number; offset?: number } = {}) {
  const where: string[] = ["s.kind != 'creator'"];
  const args: (string | number)[] = [];
  if (opts.origin) { where.push("s.origin = ?"); args.push(opts.origin); }
  if (opts.status) { where.push("s.status = ?"); args.push(opts.status); }
  if (opts.verdict === "none") where.push("w.verdict IS NULL");
  else if (opts.verdict === "any") where.push("w.verdict IS NOT NULL");
  else if (opts.verdict) { where.push("w.verdict = ?"); args.push(opts.verdict); }
  const sql = `SELECT ${SOURCE_COLS}, (SELECT hero FROM scenes c WHERE c.source_id = s.id ORDER BY COALESCE(c.quality,0) DESC, c.idx LIMIT 1) AS cover,
      (SELECT COUNT(*) FROM scenes c WHERE c.source_id = s.id) AS scene_count
    FROM sources s LEFT JOIN swipes w ON w.source_id = s.id WHERE ${where.join(" AND ")}
    ORDER BY COALESCE(w.at, s.added_at) DESC LIMIT ? OFFSET ?`;
  return all<Source & { cover: string | null; scene_count: number }>(sql, [...args, opts.limit ?? 50, opts.offset ?? 0]);
}

export async function searchScenes(q: { text?: string; tags?: string[]; liked?: boolean; limit?: number }) {
  const where: string[] = [];
  const args: (string | number)[] = [];
  for (const t of q.tags ?? []) {
    const [facet, tag] = t.includes(":") ? t.split(":", 2) : [null, t];
    where.push(`EXISTS (SELECT 1 FROM scene_tags x WHERE x.scene_id = c.id AND x.tag = ? ${facet ? "AND x.facet = ?" : ""})`);
    args.push(tag.toLowerCase()); if (facet) args.push(facet);
  }
  if (q.text) {
    where.push("(c.title LIKE ? OR c.description LIKE ? OR c.tags LIKE ? OR s.title LIKE ? OR s.author LIKE ?)");
    const like = `%${q.text}%`; args.push(like, like, like, like, like);
  }
  if (q.liked) where.push("COALESCE(w.verdict, CASE WHEN s.origin = 'seed' THEN 'like' END) = 'like'");
  const sql = `SELECT c.*, s.title AS source_title, s.author AS source_author, s.url AS source_url, w.verdict AS verdict
    FROM scenes c JOIN sources s ON s.id = c.source_id LEFT JOIN swipes w ON w.source_id = s.id
    ${where.length ? "WHERE " + where.join(" AND ") : ""}
    ORDER BY COALESCE(c.quality, 0) DESC, s.added_at DESC LIMIT ?`;
  const rows = await all(sql, [...args, q.limit ?? 30]);
  return rows.map((r) => ({ ...parseScene(r), source_title: r.source_title as string, source_author: r.source_author as string, source_url: r.source_url as string, verdict: r.verdict as string | null }));
}

export async function tagCounts() {
  return all<{ facet: string; tag: string; n: number }>(
    "SELECT facet, tag, COUNT(*) AS n FROM scene_tags GROUP BY facet, tag ORDER BY n DESC");
}

export async function stats() {
  return one<Record<string, number>>(`SELECT
    (SELECT COUNT(*) FROM sources WHERE kind != 'creator') AS sources,
    (SELECT COUNT(*) FROM sources WHERE status = 'tagged') AS tagged,
    (SELECT COUNT(*) FROM sources WHERE status = 'error') AS errors,
    (SELECT COUNT(*) FROM sources WHERE status = 'queued') AS queued,
    (SELECT COUNT(*) FROM scenes) AS scenes,
    (SELECT COUNT(*) FROM swipes WHERE verdict = 'like') AS likes,
    (SELECT COUNT(*) FROM swipes WHERE verdict = 'dislike') AS dislikes`);
}

export async function addCandidate(input: { url: string; origin: string; pitch?: string; title?: string }) {
  const { classify } = await import("@/lib/classify");
  const c = classify(input.url);
  const existing = await one<{ id: string; status: string }>("SELECT id, status FROM sources WHERE id = ?", [c.id]);
  if (existing) return { id: c.id, status: existing.status, duplicate: true };
  await run(
    `INSERT INTO sources (id, platform, kind, url, title, added_at, origin, status, pitch) VALUES (?,?,?,?,?,?,?,?,?)`,
    [c.id, c.platform, c.kind, c.url, input.title ?? "", new Date().toISOString(), input.origin,
      c.kind === "creator" ? "seed" : "queued", input.pitch ?? ""]);
  return { id: c.id, status: c.kind === "creator" ? "seed" : "queued", duplicate: false };
}
