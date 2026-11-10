import { appUrl } from "@/lib/auth";
import { grokAuthorized, grokBrief } from "@/lib/grok";

export const dynamic = "force-dynamic";
/** What Grokbot should hunt for today. Auth: ?token=<GROK_SECRET>. */
export async function GET(req: Request) {
  if (!grokAuthorized(req)) return Response.json({ error: "bad token" }, { status: 401 });
  return Response.json(await grokBrief(appUrl(req)));
}
