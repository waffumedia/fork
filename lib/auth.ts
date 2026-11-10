import { timingSafeEqual } from "node:crypto";

/** Single-owner auth: `Authorization: Bearer <INSPO_TOKEN>`, `?token=`, or the `inspo_token` cookie. */
export function safeEq(a: string, b: string) {
  const x = Buffer.from(a), y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}

export function presentedToken(req: Request): string {
  const h = req.headers.get("authorization") ?? "";
  if (/^bearer\s/i.test(h)) return h.replace(/^bearer\s+/i, "").trim();
  const q = new URL(req.url).searchParams.get("token");
  if (q) return q;
  const c = (req.headers.get("cookie") ?? "").match(/(?:^|;\s*)inspo_token=([^;]+)/);
  return c ? decodeURIComponent(c[1]) : "";
}

export function isAuthorized(req: Request): boolean {
  const want = process.env.INSPO_TOKEN;
  if (!want) return process.env.NODE_ENV !== "production"; // dev without a token stays open locally
  return safeEq(presentedToken(req), want);
}

export function appUrl(req: Request): string {
  if (process.env.APP_URL) return process.env.APP_URL.replace(/\/$/, "");
  const u = new URL(req.url);
  const proto = req.headers.get("x-forwarded-proto") ?? u.protocol.replace(":", "");
  const host = req.headers.get("x-forwarded-host") ?? req.headers.get("host") ?? u.host;
  return `${proto}://${host}`;
}

export const unauthorized = () =>
  Response.json({ error: "unauthorized" }, { status: 401, headers: { "WWW-Authenticate": 'Bearer realm="inspo"' } });

/** Wrap a route handler with owner auth + JSON error handling. */
export function owner<A extends unknown[]>(fn: (req: Request, ...rest: A) => Promise<Response>) {
  return async (req: Request, ...rest: A) => {
    if (!isAuthorized(req)) return unauthorized();
    try { return await fn(req, ...rest); }
    catch (e) { return Response.json({ error: (e as Error).message }, { status: 400 }); }
  };
}
