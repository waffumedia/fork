import { all } from "@/lib/db";
import { getSource, mediaUrl } from "@/lib/library";

/** Boards = Figma-style canvases. One per account (every source by that author) and one per video (= a source). */

export async function listBoards(base = "") {
  const accounts = await all<{ author: string; platform: string; sources: number; scenes: number; liked: number }>(`
    SELECT s.author, s.platform, COUNT(DISTINCT s.id) AS sources, COUNT(c.id) AS scenes,
      SUM(CASE WHEN COALESCE(w.verdict, CASE WHEN s.origin='seed' THEN 'like' END) = 'like' THEN 1 ELSE 0 END) AS liked
    FROM sources s LEFT JOIN scenes c ON c.source_id = s.id LEFT JOIN swipes w ON w.source_id = s.id
    WHERE s.kind != 'creator' AND s.author != ''
    GROUP BY s.author, s.platform ORDER BY sources DESC, scenes DESC`);
  const covers = await all<{ author: string; hero: string }>(`
    SELECT s.author, c.hero FROM scenes c JOIN sources s ON s.id = c.source_id
    WHERE s.author != '' ORDER BY COALESCE(c.quality,0) DESC, c.id`);
  const byAuthor = new Map<string, string[]>();
  for (const c of covers) {
    const a = byAuthor.get(c.author) ?? [];
    if (a.length < 4) a.push(mediaUrl(c.hero, base));
    byAuthor.set(c.author, a);
  }
  const videos = await all<{ id: string; title: string; author: string; platform: string; scenes: number; cover: string | null; note: string }>(`
    SELECT s.id, s.title, s.author, s.platform, s.note, COUNT(c.id) AS scenes,
      (SELECT hero FROM scenes x WHERE x.source_id = s.id ORDER BY COALESCE(x.quality,0) DESC, x.idx LIMIT 1) AS cover
    FROM sources s LEFT JOIN scenes c ON c.source_id = s.id
    WHERE s.kind != 'creator' GROUP BY s.id ORDER BY s.added_at DESC`);
  const creatorSeeds = await all<{ url: string }>("SELECT url FROM sources WHERE kind = 'creator'");
  return {
    accounts: accounts.map((a) => ({ id: `account:${a.author}`, handle: a.author, platform: a.platform, sources: a.sources, scenes: a.scenes, liked_scenes: a.liked, covers: byAuthor.get(a.author) ?? [],
      profile: a.platform === "x" ? `https://x.com/${a.author}` : null })),
    videos: videos.map((v) => ({ id: `video:${v.id}`, source_id: v.id, title: v.title, author: v.author, platform: v.platform, scenes: v.scenes, note: v.note, cover: v.cover ? mediaUrl(v.cover, base) : null })),
    creator_seeds: creatorSeeds.map((c) => c.url),
  };
}

type BoardScene = { id: string; image: string; frames: string[]; timestamp: string | null; title: string; link: string; tags: unknown; quality: number | null };
type BoardGroup = { source_id: string; title: string; url: string; note: string; verdict: string | null; origin: string; scenes: BoardScene[] };

async function group(id: string, base: string): Promise<BoardGroup | null> {
  const s = await getSource(id);
  if (!s) return null;
  return {
    source_id: s.id, title: s.title, url: s.url, note: s.note, verdict: s.verdict ?? null, origin: s.origin,
    scenes: s.scenes.map((c) => ({ id: c.id, image: mediaUrl(c.hero, base), frames: c.frames.map((f) => mediaUrl(f, base)), timestamp: c.timestamp, title: c.title, link: c.link, tags: c.tags, quality: c.quality })),
  };
}

/** board id: "account:<handle>" or "video:<source id>". Groups = one column/frame per source, scenes in order. */
export async function getBoard(boardId: string, base = "") {
  const [kind, ...rest] = boardId.split(":");
  const key = rest.join(":");
  if (kind === "video") {
    const g = await group(key, base);
    return g ? { id: boardId, kind: "video", title: g.title || key, subtitle: "", groups: [g] } : null;
  }
  if (kind === "account") {
    const ids = await all<{ id: string; platform: string }>("SELECT id, platform FROM sources WHERE author = ? AND kind != 'creator' ORDER BY posted_at DESC, added_at DESC", [key]);
    if (!ids.length) return null;
    const groups = (await Promise.all(ids.map((i) => group(i.id, base)))).filter(Boolean) as BoardGroup[];
    return { id: boardId, kind: "account", title: `@${key}`, subtitle: `${groups.length} posts · ${groups.reduce((a, g) => a + g.scenes.length, 0)} scenes`,
      profile: ids[0].platform === "x" ? `https://x.com/${key}` : null, groups };
  }
  return null;
}
