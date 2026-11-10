import { createHmac } from "node:crypto";
import { getSetting } from "@/lib/db";
import { safeEq } from "@/lib/auth";
import { tasteProfile } from "@/lib/taste";
import { all } from "@/lib/db";

/**
 * Grokbot bridge.
 * Inbound  POST /api/grok/inbox?token=<GROK_SECRET>  {"items":[{"url","pitch?","title?"}]}
 *          (also GET /api/grok/inbox?token=..&url=..&pitch=.. for bots that can only fetch URLs;
 *           or header X-Inspo-Signature: sha256=<hmac(body)>)
 * Brief    GET  /api/grok/brief?token=<GROK_SECRET>  -> what to look for, what to skip.
 * Outbound when a day's 10 are all swiped we POST the result + updated taste to `grok_webhook_url` (settings).
 */
export const sign = (secret: string, body: string) => "sha256=" + createHmac("sha256", secret).update(body).digest("hex");

export function grokAuthorized(req: Request, raw = ""): boolean {
  const secret = process.env.GROK_SECRET;
  if (!secret) return false;
  const u = new URL(req.url);
  const token = u.searchParams.get("token") ?? (req.headers.get("authorization") ?? "").replace(/^bearer\s+/i, "");
  if (token && safeEq(token, secret)) return true;
  const sig = req.headers.get("x-inspo-signature");
  return !!sig && safeEq(sig, sign(secret, raw));
}

export async function notifyGrok(payload: unknown): Promise<{ ok: boolean; status?: number; error?: string }> {
  const url = process.env.GROK_WEBHOOK_URL || (await getSetting("grok_webhook_url"));
  const secret = process.env.GROK_SECRET;
  if (!url || !secret) return { ok: false, error: "not_configured" };
  const auth = process.env.GROK_WEBHOOK_AUTH || (await getSetting("grok_webhook_auth")) || "";
  const body = JSON.stringify(payload);
  try {
    const r = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Inspo-Signature": sign(secret, body), ...(auth ? { Authorization: auth } : {}) },
      body,
      signal: AbortSignal.timeout(10_000),
    });
    return { ok: r.ok, status: r.status };
  } catch (e) {
    return { ok: false, error: (e as Error).message };
  }
}

export async function grokBrief(base: string) {
  const taste = await tasteProfile();
  const have = await all<{ url: string }>("SELECT url FROM sources WHERE kind != 'creator' ORDER BY added_at DESC LIMIT 400");
  return {
    task: "Find 10 NEW pieces of motion design, design, or standout video edits the owner has not seen. Each must be a direct link to ONE post/video (X status, YouTube video, Instagram reel, Pinterest pin). Prefer craft-heavy, portfolio-grade work from small and mid creators over viral reposts. Mix: ~7 that match the taste below, ~3 wildcards from adjacent genres that share techniques.",
    submit: {
      method: "POST",
      url: `${base}/api/grok/inbox?token=<same token>`,
      body: { items: [{ url: "https://x.com/user/status/123", pitch: "why it fits, <= 20 words", title: "optional" }] },
      fetch_only_alternative: `${base}/api/grok/inbox?token=<same token>&url=<urlencoded link>&pitch=<urlencoded why>`,
    },
    taste: taste.summary,
    taste_detail: taste.facets,
    liked_creators: taste.liked_creators,
    seed_creators: taste.seed_creators,
    already_have: have.map((h) => h.url),
    rules: ["No duplicates of links already sent", "No tutorials-only or talking-head content unless the visuals are the point", "No AI slop compilations"],
  };
}
