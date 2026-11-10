import { createMcpHandler } from "mcp-handler";
import { appUrl, isAuthorized, unauthorized } from "@/lib/auth";
import { registerTools, SERVER_INSTRUCTIONS } from "@/lib/mcp";

/** MCP (Streamable HTTP) at /api/mcp. Auth: Bearer <INSPO_TOKEN> or ?token=. */
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

async function handle(req: Request): Promise<Response> {
  if (!isAuthorized(req)) return unauthorized();
  const handler = createMcpHandler((server) => registerTools(server, { baseUrl: appUrl(req) }), {
    serverInfo: { name: "inspo", version: "0.1.0" },
    instructions: SERVER_INSTRUCTIONS,
  });
  return handler(req);
}

export { handle as GET, handle as POST, handle as DELETE };
