#!/usr/bin/env node
/**
 * Minify all Lua source files from lib/ and ecnet2/ into dist/.
 * Uses the globally installed `luamin` (npm) CLI.
 *
 * Usage:
 *   node minify.js
 *
 * Requirements:
 *   npm install -g luamin
 *
 * What it does:
 *   1. Finds all .lua files in lib/ and ecnet2/
 *   2. Minifies each via `cat file | luamin -c`
 *   3. Writes to dist/ preserving directory structure
 *   4. Reports size comparison
 */

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const ROOT = __dirname;
const DIST = path.join(ROOT, "dist");

// Extensions to process
const EXT = ".lua";

// Source directories to minify
const SOURCE_DIRS = ["lib", "ecnet2"];

function findLuaFiles(dir, rootDir) {
  const results = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...findLuaFiles(full, rootDir));
    } else if (entry.isFile() && entry.name.endsWith(EXT)) {
      results.push({
        src: full,
        rel: path.relative(rootDir, full),
      });
    }
  }
  return results;
}

function minifyFile(srcPath, dstPath) {
  const cmd = `cat ${JSON.stringify(srcPath)} | luamin -c`;
  const stdout = execSync(cmd, { encoding: "utf-8", timeout: 60000 });

  if (!stdout || stdout.startsWith("Error:")) {
    throw new Error(`luamin failed on ${srcPath}: ${stdout || "(empty output)"}`);
  }

  fs.writeFileSync(dstPath, stdout, "utf-8");
  return {
    origSize: fs.statSync(srcPath).size,
    minSize: fs.statSync(dstPath).size,
  };
}

function main() {
  // Collect all source files from each source dir
  const files = [];
  for (const dir of SOURCE_DIRS) {
    const dirPath = path.join(ROOT, dir);
    if (!fs.existsSync(dirPath)) {
      console.warn(`  ⚠  Source directory "${dir}" does not exist, skipping.`);
      continue;
    }
    files.push(...findLuaFiles(dirPath, ROOT));
  }

  if (files.length === 0) {
    console.error("No .lua files found in lib/ or ecnet2/.");
    process.exit(1);
  }

  // Ensure dist directory exists
  fs.mkdirSync(DIST, { recursive: true });

  console.log(`Found ${files.length} Lua file(s) to process.\n`);

  let totalOrig = 0;
  let totalMin = 0;
  const results = [];

  for (const file of files) {
    const dst = path.join(DIST, file.rel);
    fs.mkdirSync(path.dirname(dst), { recursive: true });

    try {
      const stats = minifyFile(file.src, dst);
      stats.file = file.rel;
      stats.pct = stats.origSize > 0
        ? ((stats.minSize / stats.origSize) * 100).toFixed(1)
        : "0.0";
      results.push(stats);
      totalOrig += stats.origSize;
      totalMin += stats.minSize;
    } catch (err) {
      console.error(`  FAIL  ${file.rel}: ${err.message}`);
    }
  }

  // Print results table
  const labelPad = Math.max(...results.map((r) => r.file.length)) + 2;
  const sep = "─".repeat(labelPad + 48);

  console.log(sep);
  console.log(
    "  File".padEnd(labelPad + 2) +
    "Original".padStart(10) +
    "Minified".padStart(11) +
    "Ratio".padStart(8)
  );
  console.log(sep);

  for (const r of results) {
    console.log(
      `  ${r.file.padEnd(labelPad)}` +
      `${fmt(r.origSize).padStart(10)}` +
      `${fmt(r.minSize).padStart(11)}` +
      `${r.pct.padStart(6)}%`
    );
  }

  console.log(sep);
  console.log(
    `  TOTAL`.padEnd(labelPad + 2) +
    `${fmt(totalOrig).padStart(10)}` +
    `${fmt(totalMin).padStart(11)}` +
    `${((totalMin / totalOrig) * 100).toFixed(1).padStart(6)}%` +
    `  (${fmt(totalOrig - totalMin)} saved)`.padStart(16)
  );
  console.log(sep);
  console.log(`\n✅ dist/ directory updated with ${results.length} files.`);
}

function fmt(bytes) {
  if (bytes >= 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + " MB";
  if (bytes >= 1024) return (bytes / 1024).toFixed(1) + " KB";
  return bytes + " B";
}

main();
