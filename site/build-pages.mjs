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

// Changelog: every ReleaseNotes/X.Y.Z.html, newest first.
const versionKey = (v) => v.split(".").map((n) => n.padStart(4, "0")).join(".");
const notes = existsSync("ReleaseNotes")
  ? readdirSync("ReleaseNotes").filter((f) => f.endsWith(".html")).map((f) => f.replace(/\.html$/, ""))
      .sort((a, b) => versionKey(b).localeCompare(versionKey(a)))
  : [];
const entries = notes.map((v) => `<section>${readFileSync(`ReleaseNotes/${v}.html`, "utf8")}</section>`).join("\n");
page("changelog", "Changelog", `<h1>Changelog</h1>\n${entries}`);

console.log(`Pages: privacy, terms, licenses, changelog (${notes.length} release${notes.length === 1 ? "" : "s"})`);
