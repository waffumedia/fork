import { appUrl, owner } from "@/lib/auth";
import { getScene, mediaUrl } from "@/lib/library";

export const dynamic = "force-dynamic";
export const GET = owner(async (req, ctx: { params: Promise<{ id: string }> }) => {
  const s = await getScene(decodeURIComponent((await ctx.params).id));
  if (!s) return Response.json({ error: "not found" }, { status: 404 });
  const base = appUrl(req);
  return Response.json({ ...s, image: mediaUrl(s.hero, base), frame_urls: s.frames.map((f) => mediaUrl(f, base)) });
});
