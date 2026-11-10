import { appUrl, owner } from "@/lib/auth";
import { getBoard } from "@/lib/boards";

export const dynamic = "force-dynamic";
/** /api/boards/account:<handle> or /api/boards/video:<source id> */
export const GET = owner(async (req, ctx: { params: Promise<{ id: string }> }) => {
  const b = await getBoard(decodeURIComponent((await ctx.params).id), appUrl(req));
  return b ? Response.json(b) : Response.json({ error: "not found" }, { status: 404 });
});
