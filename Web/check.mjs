import assert from "node:assert/strict";
import { readFile, access } from "node:fs/promises";
import { execFileSync } from "node:child_process";

// Node's parser checks all JavaScript delimiter pairs, including template expressions.
for (const file of ["dist/app.js", "serve.mjs", "check.mjs"]) {
  execFileSync(process.execPath, ["--check", file], { stdio: "inherit" });
}

const css = await readFile("dist/style.css", "utf8");
const stripped = css
  .replace(/\/\*[\s\S]*?\*\//g, "")
  .replace(/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/g, "");
const stack = [];
const pairs = { "}": "{", ")": "(", "]": "[" };
for (const char of stripped) {
  if ("{([".includes(char)) stack.push(char);
  if ("})]".includes(char))
    assert.equal(stack.pop(), pairs[char], `Unbalanced CSS ${char}`);
}
assert.equal(stack.length, 0, "Unclosed CSS delimiters");
assert.ok(
  !/https?:\/\//.test(css),
  "Styles must work without external requests",
);

const html = await readFile("dist/index.html", "utf8");
const tags = [];
const voidTags = new Set(["meta", "link", "input", "img", "br", "hr"]);
for (const [, closing, tag] of html.matchAll(
  /<(\/)?([a-z][a-z0-9]*)\b[^>]*>/gi,
)) {
  if (voidTags.has(tag)) continue;
  if (closing) assert.equal(tags.pop(), tag, `Unbalanced HTML ${tag}`);
  else tags.push(tag);
}
assert.equal(tags.length, 0, "Unclosed HTML elements");
for (const [, file] of html.matchAll(/(?:href|src)="([^"#]+)"/g))
  await access(`dist/${file}`);
const assets = JSON.parse(await readFile("assets.json", "utf8"));
for (const name of Object.keys(assets).filter((name) => name.endsWith(".jpg")))
  await access(`dist/assets/${name}`);
assert.ok(
  !/\b(?:fetch|WebSocket|XMLHttpRequest)\s*\(/.test(
    await readFile("dist/app.js", "utf8"),
  ),
  "Demo must not connect to a backend",
);
console.log(
  "Passed: JavaScript syntax, delimiter balance, local assets, and offline frontend checks.",
);
