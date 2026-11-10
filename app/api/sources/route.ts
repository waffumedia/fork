import { z } from "zod";
import { appUrl, owner } from "@/lib/auth";
import { addCandidate, listSources, mediaUrl } from "@/lib/library";

export const dynamic = "force-dynamic";
export const GET = owner(async (req) => {
  const q = new URL(req.url).searchParams;
  const rows = await listSources({ origin: q.get("origin") ?? undefined, status: q.get("status") ?? undefined, verdict: q.get("verdict") ?? undefined, limit: Number(q.get("limit") ?? 100), offset: Number(q.get("offset") ?? 0) });
  return Response.json({ items: rows.map((r) => ({ ...r, cover: r.cover ? mediaUrl(r.cover, appUrl(req)) : null })) });
});
/** Owner adds a link by hand: {"url": "...", "note"?: "..."} */
export const POST = owner(async (req) => {
  const b = z.object({ url: z.string().url(), note: z.string().optional() }).parse(await req.json());
  return Response.json(await addCandidate({ url: b.url, origin: "manual", pitch: b.note }));
});
