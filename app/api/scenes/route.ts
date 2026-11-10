import { appUrl, owner } from "@/lib/auth";
import { mediaUrl, searchScenes } from "@/lib/library";

export const dynamic = "force-dynamic";
/** ?q=text &tag=technique:kinetic-type (repeatable) &liked=1 &limit=30 */
export const GET = owner(async (req) => {
  const q = new URL(req.url).searchParams;
  const rows = await searchScenes({ text: q.get("q") ?? undefined, tags: q.getAll("tag"), liked: q.get("liked") === "1", limit: Number(q.get("limit") ?? 30) });
  const base = appUrl(req);
  return Response.json({ items: rows.map((r) => ({ ...r, image: mediaUrl(r.hero, base) })) });
});
