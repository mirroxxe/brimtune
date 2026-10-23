// Turns the Markdown legal texts and the HTML release notes into site pages.
// Usage: node site/build-pages.mjs <output dir>   (run from the repo root; deploy.sh does this)
import { readFileSync, writeFileSync, readdirSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";

const out = process.argv[2];
const template = readFileSync("site/doc-template.html", "utf8");
const today = new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });

// Markdown via the marked CLI (fetched by npx on first use).
const markdown = (file) =>
  execFileSync("npx", ["--yes", "marked@14.1.4", "-i", file], { encoding: "utf8" })
    // Links between the Markdown files point at their site pages.
    .replaceAll('href="privacy-policy.md"', 'href="/privacy"')
    .replaceAll('href="terms-of-use.md"', 'href="/terms"')
    .replaceAll("[DATE]", today);

const page = (name, title, content) =>
  writeFileSync(`${out}/${name}.html`, template.replace("{{TITLE}}", title).replace("{{CONTENT}}", content));

page("privacy", "Privacy Policy", markdown("Legal/privacy-policy.md"));
page("terms", "Terms of Use", markdown("Legal/terms-of-use.md"));
page("licenses", "Third-party notices", markdown("Legal/third-party-notices.md"));

// Changelog: every ReleaseNotes/X.Y.Z.html, newest first, dated by the commit that added it.
// The newest one also goes on the home page, in place of <!-- whats-new -->.
const versionKey = (v) => v.split(".").map((n) => n.padStart(4, "0")).join(".");
const notes = existsSync("ReleaseNotes")
  ? readdirSync("ReleaseNotes").filter((f) => f.endsWith(".html")).map((f) => f.replace(/\.html$/, ""))
      .sort((a, b) => versionKey(b).localeCompare(versionKey(a)))
  : [];
const releaseDate = (v) => {
  let iso = "";
  try { iso = execFileSync("git", ["log", "--diff-filter=A", "--format=%as", "--", `ReleaseNotes/${v}.html`], { encoding: "utf8" }).trim().split("\n").pop(); } catch {}
  const date = iso ? new Date(`${iso}T12:00:00Z`) : new Date();
  return { iso: date.toISOString().slice(0, 10), text: date.toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) };
};
// The notes' own "Brimtune X.Y.Z" heading is replaced by ours, with the date.
const changes = (v) => readFileSync(`ReleaseNotes/${v}.html`, "utf8").replace(/<h2>[\s\S]*?<\/h2>/, "").trim();
const entries = notes.map((v, i) => {
  const d = releaseDate(v);
  return `<section class="release" id="v${v}">
  <header><h2>Brimtune ${v}</h2>${i === 0 ? '<span class="latest">Latest</span>' : ""}<time datetime="${d.iso}">${d.text}</time></header>
  ${changes(v)}
</section>`;
}).join("\n");
page("changelog", "What's new", `<h1>What's new</h1>
<p class="lede-doc">Every Brimtune update, newest first. Brimtune installs updates by itself; to look right away, choose Check for Updates in its menu bar icon.</p>
${entries}`);

if (notes.length && existsSync(`${out}/index.html`)) {
  // The three newest releases, as cards.
  const block = notes.slice(0, 3).map((v, i) => {
    const d = releaseDate(v);
    return `<article class="whats-card">
            <p class="whats-version"><strong>${v}</strong>${i === 0 ? '<span class="latest">Latest</span>' : ""}<time datetime="${d.iso}">${d.text}</time></p>
            ${changes(v)}
          </article>`;
  }).join("\n          ");
  const home = readFileSync(`${out}/index.html`, "utf8");
  writeFileSync(`${out}/index.html`, home.replace("<!-- whats-new -->", block));
}

console.log(`Pages: privacy, terms, licenses, changelog (${notes.length} release${notes.length === 1 ? "" : "s"})`);
