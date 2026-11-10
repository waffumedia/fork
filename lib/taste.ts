import { all, one, run } from "@/lib/db";
import { FACETS, listSources, mediaUrl } from "@/lib/library";

/**
 * Taste = weight per facet:tag learned from swipes.
 * like = +1, dislike = -1, a seed (a link the owner hand-picked) = +1: seeds are already goated.
 * Each source's vote is spread over its scenes so long videos don't dominate.
 */
const SEED_WEIGHT = 1;
const TAG_FACETS = FACETS.filter((f) => f !== "palette");

export function today(tz = process.env.FORK_TZ || "America/Winnipeg"): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
}

type Weight = { facet: string; tag: string; score: number; likes: number; dislikes: number };

export async function tasteWeights(): Promise<Weight[]> {
  const rows = await all<{ facet: string; tag: string; vote: number; n: number }>(`
    WITH votes AS (
      SELECT s.id, CASE WHEN w.verdict = 'like' THEN 1.0 WHEN w.verdict = 'dislike' THEN -1.0
                        WHEN s.origin = 'seed' THEN ${SEED_WEIGHT} ELSE 0 END AS vote,
             (SELECT COUNT(*) FROM scenes c WHERE c.source_id = s.id) AS n
      FROM sources s LEFT JOIN swipes w ON w.source_id = s.id
    )
    SELECT t.facet, t.tag, v.vote, v.n FROM votes v
    JOIN scenes c ON c.source_id = v.id JOIN scene_tags t ON t.scene_id = c.id
    WHERE v.vote != 0 AND v.n > 0`);
  const m = new Map<string, Weight>();
  for (const r of rows) {
    const k = `${r.facet}:${r.tag}`;
    const w = m.get(k) ?? { facet: r.facet, tag: r.tag, score: 0, likes: 0, dislikes: 0 };
    w.score += r.vote / r.n;
    if (r.vote > 0) w.likes += 1 / r.n; else w.dislikes += 1 / r.n;
    m.set(k, w);
  }
  return [...m.values()].sort((a, b) => b.score - a.score);
}

export async function tasteProfile() {
  const weights = await tasteWeights();
  const byFacet: Record<string, { loves: string[]; avoids: string[] }> = {};
  for (const f of TAG_FACETS) {
    const ws = weights.filter((w) => w.facet === f);
    byFacet[f] = {
      loves: ws.filter((w) => w.score > 0.3).slice(0, 12).map((w) => w.tag),
      avoids: ws.filter((w) => w.score < -0.3).sort((a, b) => a.score - b.score).slice(0, 8).map((w) => w.tag),
    };
  }
  const counts = await one<{ likes: number; dislikes: number; seeds: number }>(`SELECT
    (SELECT COUNT(*) FROM swipes WHERE verdict='like') AS likes,
    (SELECT COUNT(*) FROM swipes WHERE verdict='dislike') AS dislikes,
    (SELECT COUNT(*) FROM sources WHERE origin='seed' AND kind != 'creator') AS seeds`);
  const creators = await all<{ author: string; n: number }>(`SELECT s.author, COUNT(*) AS n FROM sources s
    LEFT JOIN swipes w ON w.source_id = s.id
    WHERE s.author != '' AND COALESCE(w.verdict, CASE WHEN s.origin='seed' THEN 'like' END) = 'like'
    GROUP BY s.author ORDER BY n DESC LIMIT 15`);
  const seedCreators = await all<{ url: string }>("SELECT url FROM sources WHERE kind = 'creator'");
  return {
    summary: summarize(byFacet),
    counts,
    facets: byFacet,
    liked_creators: creators.map((c) => c.author),
    seed_creators: seedCreators.map((c) => c.url),
    top: weights.slice(0, 25).map((w) => ({ tag: `${w.facet}:${w.tag}`, score: +w.score.toFixed(2) })),
    bottom: weights.filter((w) => w.score < 0).sort((a, b) => a.score - b.score).slice(0, 15).map((w) => ({ tag: `${w.facet}:${w.tag}`, score: +w.score.toFixed(2) })),
  };
}

function summarize(f: Record<string, { loves: string[]; avoids: string[] }>): string {
  const l = (k: string, n = 5) => f[k]?.loves.slice(0, n).join(", ") || "-";
  const parts = [
    `Loves techniques: ${l("technique", 6)}.`,
    `Styles: ${l("style")}.`,
    `Formats: ${l("format")}.`,
    `Motion: ${l("motion", 3)}.`,
    `Tools: ${l("medium", 3)}.`,
  ];
  const avoid = [...(f.technique?.avoids ?? []), ...(f.style?.avoids ?? []), ...(f.format?.avoids ?? [])].slice(0, 6);
  if (avoid.length) parts.push(`Avoid: ${avoid.join(", ")}.`);
  return parts.join(" ");
}

/** Taste score of each source = mean tag weight over its scenes. */
export async function scoreSources(ids: string[]): Promise<Map<string, number>> {
  if (!ids.length) return new Map();
  const weights = new Map((await tasteWeights()).map((w) => [`${w.facet}:${w.tag}`, w.score]));
  const rows = await all<{ source_id: string; facet: string; tag: string; n: number }>(`
    SELECT c.source_id, t.facet, t.tag, (SELECT COUNT(*) FROM scenes x WHERE x.source_id = c.source_id) AS n
    FROM scenes c JOIN scene_tags t ON t.scene_id = c.id WHERE c.source_id IN (${ids.map(() => "?").join(",")})`, ids);
  const out = new Map<string, number>();
  for (const r of rows) out.set(r.source_id, (out.get(r.source_id) ?? 0) + (weights.get(`${r.facet}:${r.tag}`) ?? 0) / r.n);
  return out;
}

// ---------- daily 10 ----------

export const DAILY = 10;

export async function dailyPicks(day = today(), base = "") {
  let rows = await all<{ source_id: string }>("SELECT source_id FROM daily WHERE day = ? ORDER BY position", [day]);
  if (!rows.length) {
    rows = (await chooseDaily()).map((source_id) => ({ source_id }));
    let i = 0;
    for (const r of rows) await run("INSERT OR IGNORE INTO daily (day, source_id, position) VALUES (?,?,?)", [day, r.source_id, i++]);
  }
  const items = [];
  for (const { source_id } of rows) {
    const s = await one<Record<string, unknown>>(`SELECT s.*, w.verdict FROM sources s LEFT JOIN swipes w ON w.source_id = s.id WHERE s.id = ?`, [source_id]);
    if (!s) continue;
    const scenes = await all<{ id: string; hero: string; timestamp: string | null; title: string; link: string }>(
      "SELECT id, hero, timestamp, title, link FROM scenes WHERE source_id = ? ORDER BY COALESCE(quality,0) DESC, idx LIMIT 4", [source_id]);
    items.push({
      id: s.id, url: s.url, title: s.title, author: s.author, platform: s.platform, origin: s.origin, pitch: s.pitch,
      duration: s.duration, verdict: s.verdict ?? null,
      scenes: scenes.map((c) => ({ ...c, image: mediaUrl(c.hero, base) })),
    });
  }
  return { day, total: items.length, remaining: items.filter((i) => !i.verdict).length, items };
}

/** Grok's (and manual) picks only: best taste matches + a few wildcards. Seeds are already liked and never re-served. */
async function chooseDaily(): Promise<string[]> {
  const pool = await all<{ id: string; origin: string }>(`SELECT s.id, s.origin FROM sources s
    LEFT JOIN swipes w ON w.source_id = s.id
    WHERE w.verdict IS NULL AND s.kind != 'creator' AND s.status IN ('tagged','ready')
      AND s.id NOT IN (SELECT source_id FROM daily)
      AND EXISTS (SELECT 1 FROM scenes c WHERE c.source_id = s.id)`);
  const scores = await scoreSources(pool.map((p) => p.id));
  const rank = (xs: typeof pool) => xs.sort((a, b) => (scores.get(b.id) ?? 0) - (scores.get(a.id) ?? 0));
  const fresh = rank(pool.filter((p) => p.origin !== "seed"));
  // 7 best matches + 3 wildcards from the fresh pool keeps Grok's exploration visible
  const best = fresh.slice(0, 7);
  const wild = fresh.slice(7).sort(() => Math.random() - 0.5).slice(0, 3);
  const picks = [...best, ...wild].slice(0, DAILY).map((p) => p.id);
  return picks;
}

export async function swipe(sourceId: string, verdict: "like" | "dislike" | "clear") {
  const s = await one("SELECT id FROM sources WHERE id = ?", [sourceId]);
  if (!s) throw new Error(`unknown source ${sourceId}`);
  if (verdict === "clear") await run("DELETE FROM swipes WHERE source_id = ?", [sourceId]);
  else await run(`INSERT INTO swipes (source_id, verdict, at, day) VALUES (?,?,?,?)
      ON CONFLICT(source_id) DO UPDATE SET verdict = excluded.verdict, at = excluded.at, day = excluded.day`,
    [sourceId, verdict, new Date().toISOString(), today()]);
  return { id: sourceId, verdict };
}

export async function history(limit = 100, base = "") {
  const rows = await listSources({ limit, verdict: "any" });
  return rows.map((r) => ({
    id: r.id, title: r.title, author: r.author, url: r.url, verdict: r.verdict, at: r.swiped_at,
    cover: r.cover ? mediaUrl(r.cover, base) : null,
  }));
}
