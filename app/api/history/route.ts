import { appUrl, owner } from "@/lib/auth";
import { history } from "@/lib/taste";

export const dynamic = "force-dynamic";
export const GET = owner(async (req) => Response.json({ items: await history(Number(new URL(req.url).searchParams.get("limit") ?? 200), appUrl(req)) }));
