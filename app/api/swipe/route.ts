import { z } from "zod";
import { appUrl, owner } from "@/lib/auth";
import { dailyPicks, swipe, tasteProfile } from "@/lib/taste";
import { notifyGrok } from "@/lib/grok";

export const dynamic = "force-dynamic";
const Body = z.object({ id: z.string(), verdict: z.enum(["like", "dislike", "clear"]) });

/** Swipe right = like, left = dislike, clear = undo. When today's 10 are done, Grokbot gets the result. */
export const POST = owner(async (req) => {
  const { id, verdict } = Body.parse(await req.json());
  const r = await swipe(id, verdict);
  const day = await dailyPicks(undefined, appUrl(req));
  let grok = null;
  if (day.total && day.remaining === 0 && day.items.some((i) => i.id === id)) {
    grok = await notifyGrok({
      event: "day_complete", day: day.day,
      results: day.items.map((i) => ({ url: i.url, verdict: i.verdict, origin: i.origin })),
      taste: await tasteProfile(),
      brief_url: `${appUrl(req)}/api/grok/brief`,
    });
  }
  return Response.json({ ...r, remaining: day.remaining, grok });
});
