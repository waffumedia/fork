import { promises as fs } from "node:fs";
import path from "node:path";
import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/server";
import { addCandidate, DATA_DIR, getScene, getSource, mediaUrl, searchScenes, stats, tagCounts } from "@/lib/library";
import { dailyPicks, history, swipe, tasteProfile } from "@/lib/taste";
import { buildGraph } from "@/lib/graph";

export const SERVER_INSTRUCTIONS = `Inspo is the owner's private motion-design / design / video-edit reference library and taste web.
Every saved link (YouTube video, X post...) is split into SCENES: a screenshot, the exact timestamp, a deep link, and tags
(technique, style, format, motion, medium, palette, concepts). The owner swipes right (like) / left (dislike) on 10 picks a day;
likes, dislikes and hand-picked seeds form a taste profile.
PICK THE TOOL:
- "what's my taste / what do I like" -> get_taste_profile.
- "find references for X" / "show me scenes with Y" -> search_scenes (q = free text, tags = ["technique:kinetic-type"]); use list_ideas for the exact tag names.
- one scene in detail (see the image, get link + timestamp) -> get_scene.
- everything from one video/post -> get_source.
- how ideas connect / what links to a scene or idea -> get_taste_web (focus = scene id or "idea:technique:glitch").
- today's swipe deck -> get_today; record a swipe -> swipe.
- save a new link -> add_link (it is downloaded + tagged by the owner's Mac).
When citing a reference ALWAYS give: scene title, source link, and timestamp (e.g. "at 0:12").`;

type Content = { type: "text"; text: string } | { type: "image"; data: string; mimeType: string };
const text = (v: unknown): Content => ({ type: "text", text: typeof v === "string" ? v : JSON.stringify(v, null, 2) });

async function image(p: string): Promise<Content | null> {
  try {
    if (process.env.MEDIA_BASE_URL) {
      const r = await fetch(mediaUrl(p));
      if (!r.ok) return null;
      return { type: "image", data: Buffer.from(await r.arrayBuffer()).toString("base64"), mimeType: "image/jpeg" };
    }
    const buf = await fs.readFile(path.join(DATA_DIR, p));
    return { type: "image", data: buf.toString("base64"), mimeType: "image/jpeg" };
  } catch {
    return null;
  }
}

const cite = (base: string) => (s: { id: string; title: string; timestamp: string | null; link: string; hero: string; tags: unknown; description?: string }) => ({
  id: s.id, title: s.title, at: s.timestamp, link: s.link, image: mediaUrl(s.hero, base), description: s.description, tags: s.tags,
});

export function registerTools(server: McpServer, { baseUrl }: { baseUrl: string }) {
  server.registerTool("get_taste_profile", {
    title: "Taste profile",
    description: "The owner's learned taste: a one-paragraph summary, loved/avoided tags per facet, liked creators, top weights. Use before recommending or making anything in their style.",
    inputSchema: {},
    annotations: { readOnlyHint: true },
  }, async () => ({ content: [text(await tasteProfile())] }));

  server.registerTool("search_scenes", {
    title: "Search scenes",
    description: "Find reference scenes. Returns title, timestamp, deep link, screenshot URL, tags. Set images=N to also SEE the top N screenshots.",
    inputSchema: {
      q: z.string().optional().describe("free text: title, description, author"),
      tags: z.array(z.string()).optional().describe('exact tags, "facet:tag" or bare tag, all must match'),
      liked: z.boolean().optional().describe("only liked / hand-picked"),
      limit: z.number().int().min(1).max(60).optional(),
      images: z.number().int().min(0).max(8).optional(),
    },
    annotations: { readOnlyHint: true },
  }, async ({ q, tags, liked, limit, images }) => {
    const rows = await searchScenes({ text: q, tags, liked, limit: limit ?? 20 });
    const content: Content[] = [text({ count: rows.length, scenes: rows.map((r) => ({ ...cite(baseUrl)(r), source: { title: r.source_title, author: r.source_author, url: r.source_url } })) })];
    for (const r of rows.slice(0, images ?? 0)) { const im = await image(r.hero); if (im) content.push(im); }
    return { content };
  });

  server.registerTool("get_scene", {
    title: "Get scene",
    description: "One scene: its screenshot(s) as images, timestamp, deep link, tags, and its source.",
    inputSchema: { id: z.string().describe('scene id "<source id>:<n>"'), all_frames: z.boolean().optional() },
    annotations: { readOnlyHint: true },
  }, async ({ id, all_frames }) => {
    const s = await getScene(id);
    if (!s) return { content: [text({ error: `no scene ${id}` })], isError: true };
    const content: Content[] = [text({ ...cite(baseUrl)(s), t_start: s.t_start, t_end: s.t_end, quality: s.quality, source: { id: s.source.id, title: s.source.title, author: s.source.author, url: s.source.url, verdict: s.source.verdict ?? null } })];
    for (const f of all_frames ? s.frames : [s.hero]) { const im = await image(f); if (im) content.push(im); }
    return { content };
  });

  server.registerTool("get_source", {
    title: "Get source",
    description: "Everything from one saved video/post: metadata, the owner's verdict, and every scene with timestamp + link.",
    inputSchema: { id: z.string().describe('source id, e.g. "x-2113635171723616549" or "yt-KkK-Y7GiQ2o"') },
    annotations: { readOnlyHint: true },
  }, async ({ id }) => {
    const s = await getSource(id);
    if (!s) return { content: [text({ error: `no source ${id}` })], isError: true };
    return { content: [text({ ...s, scenes: s.scenes.map(cite(baseUrl)) })] };
  });

  server.registerTool("get_taste_web", {
    title: "Taste web",
    description: 'The connected web. mode "ideas" = concept map (ideas that co-occur). mode "full" = scenes + ideas + cross-source "bridge" edges (cross=true joins different genres). Use focus to get one node\'s neighbourhood.',
    inputSchema: {
      mode: z.enum(["full", "ideas"]).optional(),
      focus: z.string().optional().describe('scene id or "idea:<facet>:<tag>"'),
      depth: z.number().int().min(1).max(3).optional(),
      liked: z.boolean().optional(),
    },
    annotations: { readOnlyHint: true },
  }, async ({ mode, focus, depth, liked }) => {
    const g = await buildGraph({ mode: mode ?? (focus ? "full" : "ideas"), focus, depth, liked, base: baseUrl });
    const cap = 400;
    return { content: [text({ ...g, truncated: g.edges.length > cap, edges: g.edges.slice(0, cap) })] };
  });

  server.registerTool("list_ideas", {
    title: "List ideas",
    description: "Every tag in the library with its scene count, grouped by facet. Use for exact tag names.",
    inputSchema: {},
    annotations: { readOnlyHint: true },
  }, async () => {
    const rows = await tagCounts();
    const by: Record<string, Record<string, number>> = {};
    for (const r of rows) (by[r.facet] ??= {})[r.tag] = r.n;
    return { content: [text({ stats: await stats(), ideas: by })] };
  });

  server.registerTool("get_today", {
    title: "Today's swipe deck",
    description: "The 10 picks for today (Grokbot's finds first, then un-rated seeds), each with cover scenes and current verdict.",
    inputSchema: {},
    annotations: { readOnlyHint: true },
  }, async () => ({ content: [text(await dailyPicks(undefined, baseUrl))] }));

  server.registerTool("swipe", {
    title: "Swipe",
    description: "Record the owner's verdict on a source: like (swipe right), dislike (left), clear (undo). Only when the owner says so.",
    inputSchema: { id: z.string(), verdict: z.enum(["like", "dislike", "clear"]) },
  }, async ({ id, verdict }) => ({ content: [text(await swipe(id, verdict))] }));

  server.registerTool("get_history", {
    title: "Swipe history",
    description: "Recent likes and dislikes, newest first.",
    inputSchema: { limit: z.number().int().min(1).max(500).optional() },
    annotations: { readOnlyHint: true },
  }, async ({ limit }) => ({ content: [text(await history(limit ?? 100, baseUrl))] }));

  server.registerTool("add_link", {
    title: "Add link",
    description: "Save a new link (X post, YouTube video, IG reel, Pinterest pin, or a creator profile). It is queued; the owner's Mac downloads, scene-splits and tags it.",
    inputSchema: { url: z.string().url(), note: z.string().optional() },
  }, async ({ url, note }) => ({ content: [text(await addCandidate({ url, origin: "manual", pitch: note }))] }));
}
