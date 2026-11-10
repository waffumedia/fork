import { appUrl, owner } from "@/lib/auth";
import { dailyPicks } from "@/lib/taste";

export const dynamic = "force-dynamic";
/** Today's 10 picks to swipe. ?day=YYYY-MM-DD to look back. */
export const GET = owner(async (req) => {
  const day = new URL(req.url).searchParams.get("day") ?? undefined;
  return Response.json(await dailyPicks(day, appUrl(req)));
});
