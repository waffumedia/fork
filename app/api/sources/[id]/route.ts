import { appUrl, owner } from "@/lib/auth";
import { getSource, mediaUrl } from "@/lib/library";

export const dynamic = "force-dynamic";
export const GET = owner(async (req, ctx: { params: Promise<{ id: string }> }) => {
  const s = await getSource(decodeURIComponent((await ctx.params).id));
  if (!s) return Response.json({ error: "not found" }, { status: 404 });
  const base = appUrl(req);
  return Response.json({ ...s, scenes: s.scenes.map((c) => ({ ...c, image: mediaUrl(c.hero, base), frame_urls: c.frames.map((f) => mediaUrl(f, base)) })) });
});
