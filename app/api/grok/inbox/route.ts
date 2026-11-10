import { z } from "zod";
import { grokAuthorized } from "@/lib/grok";
import { addCandidate } from "@/lib/library";

export const dynamic = "force-dynamic";
const Item = z.object({ url: z.string().url(), pitch: z.string().max(500).optional(), title: z.string().max(200).optional() });
const Body = z.union([z.object({ items: z.array(Item).max(50) }), Item.transform((i) => ({ items: [i] }))]);

async function take(items: z.infer<typeof Item>[]) {
  const out = [];
  for (const i of items) {
    try { out.push(await addCandidate({ url: i.url, origin: "grok", pitch: i.pitch, title: i.title })); }
    catch (e) { out.push({ url: i.url, error: (e as Error).message }); }
  }
  return Response.json({ received: out.length, items: out });
}

/** Grokbot drops its picks here. Auth: ?token=<GROK_SECRET>, Bearer, or X-Inspo-Signature HMAC. */
export async function POST(req: Request) {
  const raw = await req.text();
  if (raw.length > 200_000) return Response.json({ error: "too large" }, { status: 413 });
  if (!grokAuthorized(req, raw)) return Response.json({ error: "bad token" }, { status: 401 });
  let json: unknown;
  try { json = JSON.parse(raw); } catch { return Response.json({ error: "invalid json" }, { status: 400 }); }
  const p = Body.safeParse(json);
  if (!p.success) return Response.json({ error: "expected {items:[{url,pitch?}]}" }, { status: 400 });
  return take(p.data.items);
}

/** Fetch-only bots: GET ?token=..&url=..&pitch=.. (url repeatable). */
export async function GET(req: Request) {
  if (!grokAuthorized(req)) return Response.json({ error: "bad token" }, { status: 401 });
  const q = new URL(req.url).searchParams;
  const urls = q.getAll("url");
  if (!urls.length) return Response.json({ ok: true, hint: "add &url=<link>&pitch=<why>" });
  return take(urls.map((url) => ({ url, pitch: q.get("pitch") ?? undefined })));
}
