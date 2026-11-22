import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = __dirname;

const SERVICE_ADAPTER = path.resolve(rootDir, "src/hybrid/serviceAdapter.ts");
const MOBILE_ADAPTER = path.resolve(rootDir, "src/hybrid/mobileAdapter.tsx");
const DRIVE_ADAPTER = path.resolve(rootDir, "src/hybrid/googleDriveAdapter.ts");
const BRAND_ADAPTER = path.resolve(rootDir, "src/hybrid/brandAssetAdapter.ts");
const FIREBASE_AUTH_STUB = path.resolve(rootDir, "src/hybrid/firebaseAuthStub.ts");
const SMARTPRO_ADAPTER = path.resolve(rootDir, "src/hybrid/smartProOfflineAdapter.tsx");

const TARGET_FIREBASE = path.resolve(rootDir, "src/firebase.ts");
const TARGET_MOBILE_DIR = path.resolve(rootDir, "src/mobile");
const TARGET_DRIVE = path.resolve(rootDir, "src/services/googleDrive.ts");
const TARGET_BRAND = path.resolve(rootDir, "src/utils/appBrand.ts");
const TARGET_SMARTPRO = path.resolve(rootDir, "src/components/erp/SmartProControlScreen.tsx");

function nasqoHybridIsolationPlugin(): Plugin {
  return {
    name: "nasqo-hybrid-isolation",
    enforce: "pre",
    resolveId(source, importer) {
      if (source === "firebase/auth" || source === "firebase/app") {
        return FIREBASE_AUTH_STUB;
      }
      if (!importer || !source.startsWith(".")) return null;
      const baseDir = path.dirname(importer.split("?")[0]);
      const resolved = path.resolve(baseDir, source);
      const clean = resolved.replace(/\.(ts|tsx|js|jsx)$/, "");

      if (clean === TARGET_FIREBASE.replace(/\.ts$/, "")) {
        return SERVICE_ADAPTER;
      }
      if ([TARGET_MOBILE_DIR, path.join(TARGET_MOBILE_DIR, "index"), path.join(TARGET_MOBILE_DIR, "Keyboard")].includes(clean)) {
        return MOBILE_ADAPTER;
      }
      if (clean === TARGET_DRIVE.replace(/\.ts$/, "")) {
        return DRIVE_ADAPTER;
      }
      if (clean === TARGET_BRAND.replace(/\.ts$/, "")) {
        return BRAND_ADAPTER;
      }
      if (clean === TARGET_SMARTPRO.replace(/\.tsx$/, "")) {
        return SMARTPRO_ADAPTER;
      }
      return null;
    },
  };
}

export default defineConfig({
  base: "./",
  publicDir: false,
  define: {
    "import.meta.env.VITE_NASQO_HYBRID": JSON.stringify("1"),
  },
  plugins: [nasqoHybridIsolationPlugin(), react()],
  build: {
    outDir: "dist/hybrid",
    emptyOutDir: true,
    assetsDir: "assets",
    sourcemap: false,
    cssCodeSplit: false,
    rollupOptions: {
      input: path.resolve(rootDir, "hybrid.html"),
      output: {
        entryFileNames: "assets/nasqo-hybrid-[hash].js",
        chunkFileNames: "assets/chunk-[name]-[hash].js",
        assetFileNames: "assets/[name]-[hash][extname]",
      },
    },
  },
});
