import { appUrl, owner } from "@/lib/auth";
import { listBoards } from "@/lib/boards";

export const dynamic = "force-dynamic";
/** Every board: accounts (all posts by one author) + videos (one source each). */
export const GET = owner(async (req) => Response.json(await listBoards(appUrl(req))));
