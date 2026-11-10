/** Mirror of pipeline/ingest.py classify(): stable ids for any link. Keep the two in sync. */
export type Classified = { id: string; platform: string; kind: "video" | "post" | "creator"; url: string };

export function classify(raw: string): Classified {
  const url = raw.trim();
  let u: URL;
  try { u = new URL(url); } catch { throw new Error(`not a URL: ${url}`); }
  const host = u.hostname.toLowerCase().replace(/^(www\.|m\.)/, "");
  if (host === "youtube.com" || host === "youtu.be") {
    let vid = host === "youtu.be" ? u.pathname.slice(1) : u.searchParams.get("v");
    if (!vid && u.pathname.includes("/shorts/")) vid = u.pathname.split("/shorts/")[1].split("/")[0];
    if (vid) return { id: `yt-${vid}`, platform: "youtube", kind: "video", url: `https://www.youtube.com/watch?v=${vid}` };
  }
  if (["x.com", "twitter.com", "fxtwitter.com", "vxtwitter.com"].includes(host)) {
    const m = u.pathname.match(/^\/([^/]+)\/status\/(\d+)/);
    if (m) return { id: `x-${m[2]}`, platform: "x", kind: "post", url: `https://x.com/${m[1]}/status/${m[2]}` };
    const handle = u.pathname.replace(/^\//, "").split("/")[0];
    if (handle) return { id: `creator-x-${handle.toLowerCase()}`, platform: "x", kind: "creator", url: `https://x.com/${handle}` };
  }
  if (host === "instagram.com") {
    const m = u.pathname.match(/^\/(?:p|reel|reels)\/([^/]+)/);
    if (m) return { id: `ig-${m[1]}`, platform: "instagram", kind: "post", url: `https://www.instagram.com/reel/${m[1]}/` };
  }
  if (host === "pinterest.com" || host.endsWith(".pinterest.com") || host === "pin.it") {
    const m = u.pathname.match(/\/pin\/(\d+)/);
    if (m) return { id: `pin-${m[1]}`, platform: "pinterest", kind: "post", url: `https://www.pinterest.com/pin/${m[1]}/` };
  }
  const slug = (host + u.pathname).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 60);
  return { id: `site-${slug}`, platform: "web", kind: "creator", url };
}
