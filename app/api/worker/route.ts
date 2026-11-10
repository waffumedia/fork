import { owner } from "@/lib/auth";
import { all } from "@/lib/db";
import { importAll, importSourceFile, DATA_DIR } from "@/lib/library";
import path from "node:path";

export const dynamic = "force-dynamic";
/** Mac worker: GET = links waiting to be downloaded + tagged. */
export const GET = owner(async () => Response.json({
  queued: await all("SELECT id, url, origin, pitch FROM sources WHERE status = 'queued' ORDER BY added_at"),
}));
/** POST {"ids":[...]} re-imports data/sources/<id>.json; {} re-imports everything. */
export const POST = owner(async (req) => {
  const b = (await req.json().catch(() => ({}))) as { ids?: string[] };
  if (!b.ids?.length) return Response.json(await importAll());
  const done = [];
  for (const id of b.ids) done.push(await importSourceFile(path.join(DATA_DIR, "sources", `${id.replace(/[^\w.-]/g, "")}.json`)));
  return Response.json({ imported: done });
});
