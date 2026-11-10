import { promises as fs } from "node:fs";
import path from "node:path";
import { DATA_DIR } from "@/lib/library";

export const dynamic = "force-dynamic";
/** Local scene screenshots (prod serves them from MEDIA_BASE_URL instead). Public: paths are opaque ids. */
export async function GET(_req: Request, ctx: { params: Promise<{ path: string[] }> }) {
  const parts = (await ctx.params).path;
  const file = path.join(DATA_DIR, "media", ...parts);
  if (!file.startsWith(path.join(DATA_DIR, "media") + path.sep) || !/\.(jpe?g|png|webp)$/i.test(file)) return new Response("not found", { status: 404 });
  try {
    const buf = await fs.readFile(file);
    return new Response(new Uint8Array(buf), { headers: { "Content-Type": "image/jpeg", "Cache-Control": "public, max-age=31536000, immutable" } });
  } catch {
    return new Response("not found", { status: 404 });
  }
}
