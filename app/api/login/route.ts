import { safeEq } from "@/lib/auth";

export const dynamic = "force-dynamic";
/** POST {"token": "..."} -> sets the fork_token cookie for the web UI. DELETE logs out. */
export async function POST(req: Request) {
  const { token } = (await req.json().catch(() => ({}))) as { token?: string };
  const want = process.env.FORK_TOKEN ?? "";
  if (!want || !token || !safeEq(token, want)) return Response.json({ error: "wrong token" }, { status: 401 });
  const secure = new URL(req.url).protocol === "https:" ? "; Secure" : "";
  return Response.json({ ok: true }, { headers: { "Set-Cookie": `fork_token=${encodeURIComponent(token)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=31536000${secure}` } });
}
export async function DELETE() {
  return Response.json({ ok: true }, { headers: { "Set-Cookie": "fork_token=; Path=/; Max-Age=0" } });
}
