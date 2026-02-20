import { defineConfig } from "zotero-plugin-scaffold";
import pkg from "./package.json";
import { cpSync, readdirSync, writeFileSync } from "fs";
import { resolve } from "path";

export default defineConfig({
  source: ["src", "addon"],
  dist: ".scaffold/build",
  name: pkg.config.addonName,
  id: pkg.config.addonID,
  namespace: pkg.config.addonRef,
  updateURL: `https://github.com/{{owner}}/{{repo}}/releases/download/release/${
    pkg.version.includes("-") ? "update-beta.json" : "update.json"
  }`,
  xpiDownloadLink:
    "https://github.com/{{owner}}/{{repo}}/releases/download/v{{version}}/{{xpiName}}.xpi",

  build: {
    assets: ["addon/**/*.*"],
    define: {
      ...pkg.config,
      author: pkg.author,
      description: pkg.description,
      homepage: pkg.homepage,
      buildVersion: pkg.version,
      buildTime: "{{buildTime}}",
    },
    prefs: {
      prefix: pkg.config.prefsPrefix,
    },
    esbuildOptions: [
      {
        entryPoints: ["src/index.ts"],
        define: {
          __env__: `"${process.env.NODE_ENV}"`,
        },
        bundle: true,
        target: "firefox115",
        outfile: `.scaffold/build/addon/content/scripts/${pkg.config.addonRef}.js`,
      },
    ],
    hooks: {
      // Copy the entire native/ tree into the XPI as addon/zotlight/native/,
      // excluding build artifacts and local tooling dirs.
      "build:copyAssets": async (ctx) => {
        const destNative = resolve(ctx.dist, "addon/zotlight/native");
        cpSync(resolve("native"), destNative, {
          recursive: true,
          filter: (src) =>
            !src.includes("/dist") &&
            !src.includes("/.claude") &&
            !src.endsWith("zotero.icns"),
        });

        // Write a MANIFEST listing all relative file paths so the runtime
        // can enumerate them via getContentsAsync (works with jar: URIs too).
        const files: string[] = [];
        const walk = (dir: string, prefix: string) => {
          for (const entry of readdirSync(dir, { withFileTypes: true })) {
            if (entry.name === ".DS_Store") continue;
            const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
            if (entry.isDirectory()) walk(resolve(dir, entry.name), rel);
            else files.push(rel);
          }
        };
        walk(destNative, "");
        writeFileSync(
          resolve(destNative, "MANIFEST"),
          files.sort().join("\n") + "\n",
        );
      },
    },
  },

  test: {
    waitForPlugin: `() => Zotero.${pkg.config.addonInstance}.data.initialized`,
  },
});
