import { all } from "@/lib/db";
import { mediaUrl } from "@/lib/library";

/**
 * The creativity web.
 *  - scene nodes (a screenshot) link to idea nodes (technique / style / format / motion / medium / concept tags)
 *  - "bridge" edges join scenes from DIFFERENT sources that share rare ideas, weighted by IDF,
 *    and are flagged `cross` when the two scenes come from different formats/genres —
 *    the "very different image types that connect" part.
 *  - mode "ideas" collapses scenes away and links ideas that co-occur (Obsidian-style concept map).
 */

type SceneRow = { id: string; source_id: string; title: string; hero: string; timestamp: string | null; link: string; quality: number | null; verdict: string | null; origin: string };
type TagRow = { scene_id: string; facet: string; tag: string };

export type GraphNode =
  | { id: string; type: "scene"; label: string; image: string; source_id: string; timestamp: string | null; link: string; liked: boolean | null; quality: number | null; degree: number }
  | { id: string; type: "idea"; label: string; facet: string; count: number; degree: number; taste?: number };
export type GraphEdge = { source: string; target: string; kind: "has" | "bridge" | "co"; weight: number; cross?: boolean; shared?: string[] };

const LINK_FACETS = ["technique", "style", "format", "motion", "medium", "concepts"];
const BRIDGE_FACETS = new Set(["technique", "style", "motion", "concepts"]);

export async function buildGraph(opts: { mode?: "full" | "ideas"; liked?: boolean; focus?: string; depth?: number; minCount?: number; base?: string } = {}) {
  const mode = opts.mode ?? "full";
  const base = opts.base ?? "";
  const scenes = await all<SceneRow>(`SELECT c.id, c.source_id, c.title, c.hero, c.timestamp, c.link, c.quality, w.verdict, s.origin
    FROM scenes c JOIN sources s ON s.id = c.source_id LEFT JOIN swipes w ON w.source_id = s.id`);
  // disliked scenes never enter the web; `liked` narrows it to likes + un-rated seeds
  const keep = new Set(scenes.filter((s) => s.verdict !== "dislike" && (!opts.liked || s.verdict === "like" || (!s.verdict && s.origin === "seed"))).map((s) => s.id));
  const tags = (await all<TagRow>(`SELECT scene_id, facet, tag FROM scene_tags WHERE facet IN (${LINK_FACETS.map(() => "?").join(",")})`, LINK_FACETS))
    .filter((t) => keep.has(t.scene_id));

  const ideaCount = new Map<string, number>();
  for (const t of tags) ideaCount.set(`${t.facet}:${t.tag}`, (ideaCount.get(`${t.facet}:${t.tag}`) ?? 0) + 1);
  const minCount = opts.minCount ?? (mode === "ideas" ? 2 : 2);
  const ideaOk = (k: string) => (ideaCount.get(k) ?? 0) >= minCount;
  const sceneTags = new Map<string, string[]>();
  for (const t of tags) {
    const k = `${t.facet}:${t.tag}`;
    if (!ideaOk(k)) continue;
    (sceneTags.get(t.scene_id) ?? sceneTags.set(t.scene_id, []).get(t.scene_id)!).push(k);
  }

  const nodes = new Map<string, GraphNode>();
  const edges: GraphEdge[] = [];
  for (const [k, n] of ideaCount) {
    if (!ideaOk(k)) continue;
    const i = k.indexOf(":"); const facet = k.slice(0, i), label = k.slice(i + 1);
    nodes.set(`idea:${k}`, { id: `idea:${k}`, type: "idea", label, facet, count: n, degree: 0 });
  }

  if (mode === "ideas") {
    const co = new Map<string, number>();
    for (const ks of sceneTags.values()) {
      for (let i = 0; i < ks.length; i++) for (let j = i + 1; j < ks.length; j++) {
        const [a, b] = ks[i] < ks[j] ? [ks[i], ks[j]] : [ks[j], ks[i]];
        co.set(`${a}|${b}`, (co.get(`${a}|${b}`) ?? 0) + 1);
      }
    }
    for (const [k, w] of co) {
      if (w < 2) continue;
      const [a, b] = k.split("|");
      edges.push({ source: `idea:${a}`, target: `idea:${b}`, kind: "co", weight: w });
    }
  } else {
    const total = Math.max(1, keep.size);
    const idf = (k: string) => Math.log(total / (ideaCount.get(k) ?? 1));
    const fmt = (id: string) => new Set((sceneTags.get(id) ?? []).filter((k) => k.startsWith("format:")));
    for (const s of scenes) {
      if (!keep.has(s.id)) continue;
      nodes.set(s.id, {
        id: s.id, type: "scene", label: s.title || s.timestamp || s.id, image: mediaUrl(s.hero, base), source_id: s.source_id,
        timestamp: s.timestamp, link: s.link, liked: s.verdict === "like" ? true : s.verdict === "dislike" ? false : null,
        quality: s.quality, degree: 0,
      });
      for (const k of sceneTags.get(s.id) ?? []) edges.push({ source: s.id, target: `idea:${k}`, kind: "has", weight: 1 });
    }
    // bridges: top-3 most similar scenes from other sources (IDF-weighted shared ideas)
    const byIdea = new Map<string, string[]>();
    for (const [sid, ks] of sceneTags) for (const k of ks) if (BRIDGE_FACETS.has(k.split(":")[0])) (byIdea.get(k) ?? byIdea.set(k, []).get(k)!).push(sid);
    const srcOf = new Map(scenes.map((s) => [s.id, s.source_id]));
    const seen = new Set<string>();
    for (const [sid, ks] of sceneTags) {
      const score = new Map<string, { w: number; shared: string[] }>();
      for (const k of ks) {
        if (!BRIDGE_FACETS.has(k.split(":")[0])) continue;
        const peers = byIdea.get(k) ?? [];
        if (peers.length > total * 0.25) continue; // too common to be interesting
        for (const p of peers) {
          if (p === sid || srcOf.get(p) === srcOf.get(sid)) continue;
          const e = score.get(p) ?? { w: 0, shared: [] };
          e.w += idf(k); e.shared.push(k); score.set(p, e);
        }
      }
      const top = [...score.entries()].filter(([, e]) => e.shared.length >= 2).sort((a, b) => b[1].w - a[1].w).slice(0, 3);
      for (const [p, e] of top) {
        const key = sid < p ? `${sid}|${p}` : `${p}|${sid}`;
        if (seen.has(key)) continue;
        seen.add(key);
        const fa = fmt(sid), fb = fmt(p);
        const cross = fa.size > 0 && fb.size > 0 && ![...fa].some((x) => fb.has(x));
        edges.push({ source: sid, target: p, kind: "bridge", weight: +e.w.toFixed(2), cross, shared: e.shared.map((s) => s.split(":")[1]) });
      }
    }
  }

  for (const e of edges) {
    const a = nodes.get(e.source), b = nodes.get(e.target);
    if (a) a.degree++;
    if (b) b.degree++;
  }
  let outNodes = [...nodes.values()].filter((n) => n.degree > 0);
  let outEdges = edges;
  if (opts.focus) {
    const want = new Set([opts.focus]);
    for (let d = 0; d < (opts.depth ?? 1); d++) {
      for (const e of outEdges) {
        if (want.has(e.source)) want.add(e.target);
        else if (want.has(e.target)) want.add(e.source);
      }
    }
    outNodes = outNodes.filter((n) => want.has(n.id));
    outEdges = outEdges.filter((e) => want.has(e.source) && want.has(e.target));
  }
  return {
    mode,
    stats: { nodes: outNodes.length, edges: outEdges.length, scenes: outNodes.filter((n) => n.type === "scene").length, ideas: outNodes.filter((n) => n.type === "idea").length, cross_bridges: outEdges.filter((e) => e.cross).length },
    nodes: outNodes,
    edges: outEdges,
  };
}
