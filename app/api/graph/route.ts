import { appUrl, owner } from "@/lib/auth";
import { buildGraph } from "@/lib/graph";

export const dynamic = "force-dynamic";
/** ?mode=full|ideas &liked=1 &focus=<node id> &depth=1 */
export const GET = owner(async (req) => {
  const q = new URL(req.url).searchParams;
  return Response.json(await buildGraph({
    mode: q.get("mode") === "ideas" ? "ideas" : "full",
    liked: q.get("liked") === "1",
    focus: q.get("focus") ?? undefined,
    depth: Number(q.get("depth") ?? 1),
    base: appUrl(req),
  }));
});
