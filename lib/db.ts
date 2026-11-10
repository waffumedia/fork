import { createClient, type Client, type InValue } from "@libsql/client";

/**
 * libSQL: Turso in production (TURSO_DATABASE_URL + TURSO_AUTH_TOKEN), local file otherwise.
 * Tables are created on first use.
 *
 * sources   one saved link (YouTube video, X post, creator profile...). `origin` = seed | grok | manual.
 * scenes    one screenshot-able scene of a source, with timestamp, deep link and VLM tags.
 * scene_tags flattened facet:tag rows for search + graph.
 * swipes    the owner's like / dislike per source (latest wins).
 * daily     the 10 picks served for a given day.
 */

let client: Client | null = null;
let ready: Promise<void> | null = null;

const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS sources (
    id TEXT PRIMARY KEY,
    platform TEXT NOT NULL,
    kind TEXT NOT NULL,
    url TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    author TEXT NOT NULL DEFAULT '',
    text TEXT NOT NULL DEFAULT '',
    posted_at TEXT,
    added_at TEXT NOT NULL,
    origin TEXT NOT NULL DEFAULT 'seed',
    status TEXT NOT NULL,
    error TEXT,
    duration REAL,
    note TEXT NOT NULL DEFAULT '',
    pitch TEXT NOT NULL DEFAULT ''
  )`,
  `CREATE TABLE IF NOT EXISTS scenes (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
    idx INTEGER NOT NULL,
    kind TEXT NOT NULL,
    t_start REAL,
    t_end REAL,
    timestamp TEXT,
    link TEXT NOT NULL,
    frames TEXT NOT NULL,
    hero TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    quality INTEGER,
    tags TEXT NOT NULL DEFAULT '{}'
  )`,
  `CREATE INDEX IF NOT EXISTS scenes_source ON scenes(source_id, idx)`,
  `CREATE TABLE IF NOT EXISTS scene_tags (
    scene_id TEXT NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
    facet TEXT NOT NULL,
    tag TEXT NOT NULL,
    PRIMARY KEY (scene_id, facet, tag)
  )`,
  `CREATE INDEX IF NOT EXISTS scene_tags_tag ON scene_tags(facet, tag)`,
  `CREATE TABLE IF NOT EXISTS swipes (
    source_id TEXT PRIMARY KEY REFERENCES sources(id) ON DELETE CASCADE,
    verdict TEXT NOT NULL CHECK (verdict IN ('like','dislike')),
    at TEXT NOT NULL,
    day TEXT NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS daily (
    day TEXT NOT NULL,
    source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    PRIMARY KEY (day, source_id)
  )`,
  `CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)`,
];

function getClient(): Client {
  if (!client) {
    client = createClient({
      url: process.env.TURSO_DATABASE_URL || `file:${process.env.FORK_DB || "local.db"}`,
      authToken: process.env.TURSO_AUTH_TOKEN || undefined,
    });
  }
  return client;
}

export async function db(): Promise<Client> {
  const c = getClient();
  if (!ready) {
    ready = (async () => {
      await c.execute("PRAGMA foreign_keys = ON");
      for (const s of SCHEMA) await c.execute(s);
    })();
  }
  await ready;
  return c;
}

export type Row = Record<string, InValue | null>;

export async function all<T = Row>(sql: string, args: InValue[] = []): Promise<T[]> {
  const r = await (await db()).execute({ sql, args });
  return r.rows as unknown as T[];
}

export async function one<T = Row>(sql: string, args: InValue[] = []): Promise<T | null> {
  return (await all<T>(sql, args))[0] ?? null;
}

export async function run(sql: string, args: InValue[] = []) {
  return (await db()).execute({ sql, args });
}

export async function getSetting(key: string): Promise<string | null> {
  return (await one<{ value: string }>("SELECT value FROM settings WHERE key = ?", [key]))?.value ?? null;
}

export async function setSetting(key: string, value: string) {
  await run("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [key, value]);
}
