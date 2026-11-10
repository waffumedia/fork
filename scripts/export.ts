/** npm run export — write data/library.json + data/LIBRARY.md (human/agent-readable index of every scene). */
import { promises as fs } from "node:fs";
import path from "node:path";
import { all } from "../lib/db";
import { DATA_DIR, getSource } from "../lib/library";
import { tasteProfile } from "../lib/taste";

async function main() {
  const ids = await all<{ id: string }>("SELECT id FROM sources ORDER BY origin, author, added_at");
  const sources = [];
  for (const { id } of ids) sources.push(await getSource(id));
  const taste = await tasteProfile();
  await fs.writeFile(path.join(DATA_DIR, "library.json"), JSON.stringify({ generated: new Date().toISOString(), taste, sources }, null, 1));
  const md: string[] = [`# Inspo library\n`, `Generated ${new Date().toISOString()} · ${sources.length} sources · ${sources.reduce((a, s) => a + (s?.scenes.length ?? 0), 0)} scenes\n`,
    `**Taste:** ${taste.summary}\n`, `Screenshots live in \`data/\` (paths below are relative to it). Scene ids work with the MCP \`get_scene\` tool.\n`];
  for (const s of sources) {
    if (!s) continue;
    const v = s.verdict === "like" ? "♥" : s.verdict === "dislike" ? "✕" : s.kind === "creator" ? "creator" : s.origin;
    md.push(`\n## ${s.title || s.id}\n${s.author ? "@" + s.author + " · " : ""}${s.platform} · ${v} · [${s.url}](${s.url}) · \`${s.id}\`\n`);
    for (const c of s.scenes) {
      const tags = Object.entries(c.tags).filter(([k]) => k !== "palette").flatMap(([, v]) => v ?? []).slice(0, 10).join(", ");
      md.push(`- **${c.timestamp ?? "image"}** ${c.title || ""} — [open](${c.link}) · \`${c.id}\` · ![](${c.hero})${tags ? `\n  ${tags}` : ""}${c.description ? `\n  ${c.description}` : ""}`);
    }
  }
  await fs.writeFile(path.join(DATA_DIR, "LIBRARY.md"), md.join("\n") + "\n");
  console.log(`exported ${sources.length} sources`);
}
main();
