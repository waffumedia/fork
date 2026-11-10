/** npm run import — load every data/sources/*.json into the database, then apply seed/owner-notes.txt ("<id> [like] <note>"). */
import { promises as fs } from "node:fs";
import { importAll } from "../lib/library";
import { run } from "../lib/db";

async function main() {
  const r = await importAll();
  const notes = await fs.readFile("seed/owner-notes.txt", "utf8").catch(() => "");
  let applied = 0;
  for (const line of notes.split("\n")) {
    const m = line.trim().match(/^(\S+)\s+(?:like\s+)?(.+?)(?:\s+\(owner note.*\))?$/);
    if (!m) continue;
    await run("UPDATE sources SET note = ? WHERE id = ?", [m[2], m[1]]);
    applied++;
  }
  console.log(JSON.stringify({ ...r, notes: applied }, null, 2));
  process.exit(r.errors.length ? 1 : 0);
}
main();
