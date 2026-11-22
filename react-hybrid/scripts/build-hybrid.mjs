import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, "..");
const outDir = path.join(rootDir, "dist", "hybrid");

console.log("[hybrid-build] Building offline React bundle for Flutter Android WebView...");

const viteBin = path.join(rootDir, "node_modules", ".bin", "vite");
execFileSync(viteBin, ["build", "--config", "vite.hybrid.config.ts"], {
  cwd: rootDir,
  stdio: "inherit",
});

// Rename hybrid.html -> index.html so Flutter WebView can load assets/web/index.html directly
const hybridHtmlPath = path.join(outDir, "hybrid.html");
const indexHtmlPath = path.join(outDir, "index.html");
if (fs.existsSync(hybridHtmlPath)) {
  fs.renameSync(hybridHtmlPath, indexHtmlPath);
}

if (!fs.existsSync(indexHtmlPath)) {
  throw new Error("[hybrid-build] Missing dist/hybrid/index.html after build.");
}

// Recursively collect files & audit offline / security guarantees
const FORBIDDEN_PATTERNS = [
  { label: "External Google Fonts CDN", regex: /fonts\.googleapis\.com|fonts\.gstatic\.com/i },
  { label: "Firebase Auth/Firestore SDK host", regex: /firebaseapp\.com|firestore\.googleapis\.com|identitytoolkit\.googleapis\.com/i },
  { label: "Web server SQLite HTTP route", regex: /\/api\/db\/workspace\//i },
  { label: "Web server SQLite Auth HTTP route", regex: /api\/db\/auth\//i },
  { label: "Web server SmartPro HTTP route", regex: /api\/smartpro\//i },
  { label: "Web server AI HTTP route", regex: /\/api\/ai\/categorize-expense/i },
  { label: "External AI Studio web origin", regex: /ai\.studio/i },
  { label: "Hardcoded Google API Key", regex: /AIza[0-9A-Za-z_-]{20,}/ },
  { label: "Mock Flutter URL/host activation", regex: /mockFlutter|installMockFlutterHost|__nasqoMockBridgeLog/i },
  { label: "Bundled test fixture data", regex: /مؤسسة البراري للتوريد|شركة الخليج للطاقة \(دولار\)|حوالات الصرافة الدولية|BAT-200/ },
];

function walkFiles(dir) {
  const results = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...walkFiles(full));
    } else {
      results.push(full);
    }
  }
  return results;
}

const allFiles = walkFiles(outDir).filter((f) => path.basename(f) !== "hybrid-manifest.json");
const manifestEntries = [];
let totalBytes = 0;
const auditViolations = [];

for (const absPath of allFiles) {
  const relPath = path.relative(outDir, absPath).split(path.sep).join("/");
  const buf = fs.readFileSync(absPath);
  const sha256 = crypto.createHash("sha256").update(buf).digest("hex");
  totalBytes += buf.byteLength;
  manifestEntries.push({
    path: relPath,
    bytes: buf.byteLength,
    sha256,
  });

  if (/\.(html|js|css)$/i.test(relPath)) {
    const text = buf.toString("utf8");
    for (const rule of FORBIDDEN_PATTERNS) {
      if (rule.regex.test(text)) {
        auditViolations.push(`${relPath}: matched forbidden pattern [${rule.label}]`);
      }
    }
  }
}

const indexHtml = fs.readFileSync(indexHtmlPath, "utf8");
if (!indexHtml.includes("Content-Security-Policy") || !indexHtml.includes("connect-src 'none'")) {
  auditViolations.push("index.html: missing strict Content-Security-Policy with connect-src 'none'");
}
if (/src=["']\/assets\//.test(indexHtml) || /href=["']\/assets\//.test(indexHtml)) {
  auditViolations.push("index.html: found root-absolute /assets/ path instead of relative ./assets/");
}

if (auditViolations.length > 0) {
  console.error("[hybrid-build] Security / offline audit FAILED:");
  for (const v of auditViolations) {
    console.error("  -", v);
  }
  process.exit(1);
}

const manifest = {
  app: "NASQO PRO ERP Hybrid React Bundle",
  protocolVersion: "1.0.0",
  bridgeChannel: "NasqoHome",
  supportedBridgeChannels: ["NasqoHome", "NasqoFlutterBridge", "flutter_inappwebview"],
  entryHtml: "index.html",
  offlineReady: true,
  cspEnforced: true,
  mockHostStripped: true,
  totalFiles: manifestEntries.length,
  totalBytes,
  files: manifestEntries.sort((a, b) => a.path.localeCompare(b.path)),
};

fs.writeFileSync(
  path.join(outDir, "hybrid-manifest.json"),
  JSON.stringify(manifest, null, 2) + "\n",
  "utf8",
);

console.log(
  `[hybrid-build] SUCCESS: ${manifest.totalFiles} files (${(totalBytes / 1024).toFixed(1)} KB) written to dist/hybrid/ with 0 security/offline violations.`,
);
