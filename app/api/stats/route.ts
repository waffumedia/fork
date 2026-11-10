import { owner } from "@/lib/auth";
import { stats, tagCounts } from "@/lib/library";

export const dynamic = "force-dynamic";
export const GET = owner(async () => Response.json({ ...(await stats()), tags: (await tagCounts()).slice(0, 80) }));
