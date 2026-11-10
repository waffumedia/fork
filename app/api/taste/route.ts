import { owner } from "@/lib/auth";
import { tasteProfile } from "@/lib/taste";

export const dynamic = "force-dynamic";
export const GET = owner(async () => Response.json(await tasteProfile()));
