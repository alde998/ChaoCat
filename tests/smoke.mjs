import fs from "node:fs/promises";
import path from "node:path";

const root = process.cwd();
const requiredFiles = [
  "apps/bridge/server.mjs",
  "apps/macos/Package.swift",
  "apps/macos/Sources/main.swift",
  "shared/protocol.js",
  "extensions/vscode/package.json",
  "extensions/vscode/extension.js",
  "extensions/obsidian/manifest.json",
  "extensions/obsidian/main.js",
  "extensions/notion-web/manifest.json",
  "extensions/notion-web/content.js"
];

const missing = [];
for (const file of requiredFiles) {
  try {
    await fs.access(path.join(root, file));
  } catch {
    missing.push(file);
  }
}

if (missing.length) {
  console.error(`Missing files:\n${missing.join("\n")}`);
  process.exit(1);
}

const protocol = await import(path.join(root, "shared/protocol.js"));
const event = protocol.makeEvent(protocol.EventType.PetActionRequested, { action: "poopChaos" }, "smoke");

if (!event.id || event.type !== "pet.actionRequested" || event.payload.action !== "poopChaos") {
  console.error("Protocol smoke check failed.");
  process.exit(1);
}

console.log("Chaos Cat smoke check passed.");
