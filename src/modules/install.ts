import { openConfig } from "./settings";

const ZOTLIGHT_APP = "/Applications/ZotLight.app";
const ZOTLIGHT_PLIST = `${ZOTLIGHT_APP}/Contents/Info.plist`;

// Must match CFBundleVersion in native/ZotLight/Info.plist
const EXPECTED_BUILD = 3;

const ZOTLIGHT_BIN = `${ZOTLIGHT_APP}/Contents/MacOS/ZotLight`;

function notify(title: string, body: string): void {
  // Use ZotLight when available so the notification carries its icon.
  // Fall back to osascript for the pre-install case (first-time setup).
  IOUtils.exists(ZOTLIGHT_BIN)
    .then((exists) => {
      if (exists) {
        Zotero.Utilities.Internal.exec(ZOTLIGHT_BIN, [
          "--notify",
          title,
          body,
        ]).catch(() => {});
      } else {
        Zotero.Utilities.Internal.exec("/usr/bin/osascript", [
          "-e",
          `display notification ${JSON.stringify(body)} with title ${JSON.stringify(title)}`,
        ]).catch(() => {});
      }
    })
    .catch(() => {});
}

export async function checkAndInstall({
  silent = false,
}: { silent?: boolean } = {}): Promise<void> {
  if (!Zotero.isMac) {
    Services.prompt.alert(
      // @ts-expect-error - Services.prompt is not typed
      null,
      "Spotlight Search",
      "ZotLight is only supported on macOS.",
    );
    return;
  }

  const installedBuild = await getInstalledBuild();
  if (installedBuild === EXPECTED_BUILD) {
    ztoolkit.log(
      `[SpotlightSearch] ZotLight is up to date (build ${EXPECTED_BUILD}).`,
    );
    if (!silent) notify("Spotlight Search", "ZotLight is already up to date.");
    return;
  }

  const statusMsg =
    installedBuild == null
      ? "ZotLight not found"
      : `ZotLight build ${installedBuild} is outdated (expected ${EXPECTED_BUILD})`;

  ztoolkit.log(`[SpotlightSearch] ${statusMsg}. Building and installing...`);
  if (!silent) notify("Spotlight Search", "Building and installing ZotLight…");

  try {
    await buildAndInstall();
    if (!silent) notify("Spotlight Search", "ZotLight installed successfully.");
    ztoolkit.log("[SpotlightSearch] ZotLight installed successfully.");
    openConfig();
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (!silent) notify("Spotlight Search", `Installation failed: ${msg}`);
    ztoolkit.log(`[SpotlightSearch] ZotLight installation failed: ${msg}`);
  }
}

export async function uninstall(): Promise<void> {
  if (!Zotero.isMac) return;

  const installedBuild = await getInstalledBuild();
  if (installedBuild === null) {
    ztoolkit.log(
      "[SpotlightSearch] ZotLight is not installed, nothing to uninstall.",
    );
    notify("Spotlight Search", "ZotLight is not installed.");
    return;
  }

  notify("Spotlight Search", "Uninstalling ZotLight…");

  try {
    await runUninstall();
    notify("Spotlight Search", "ZotLight uninstalled successfully.");
    ztoolkit.log("[SpotlightSearch] ZotLight uninstalled successfully.");
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    notify("Spotlight Search", `Uninstall failed: ${msg}`);
    ztoolkit.log(`[SpotlightSearch] ZotLight uninstall failed: ${msg}`);
  }
}

async function runUninstall(): Promise<void> {
  const tmpDir = PathUtils.join(
    PathUtils.tempDir,
    `zotlight-uninstall-${Date.now()}`,
  );

  await copyNativeDir(tmpDir);

  const r1 = await Zotero.Utilities.Internal.exec("/bin/chmod", [
    "+x",
    PathUtils.join(tmpDir, "uninstall.sh"),
  ]);
  if (r1 instanceof Error) throw r1;

  const r2 = await Zotero.Utilities.Internal.exec("/bin/bash", [
    "-c",
    'export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" && cd "$1" && bash uninstall.sh',
    "--",
    tmpDir,
  ]);
  if (r2 instanceof Error) throw r2;
}

async function getInstalledBuild(): Promise<number | null> {
  try {
    const plist = await IOUtils.readUTF8(ZOTLIGHT_PLIST);
    const match = plist.match(
      /<key>CFBundleVersion<\/key>\s*<string>(\d+)<\/string>/,
    );
    return match ? parseInt(match[1], 10) : null;
  } catch {
    return null;
  }
}

async function getContent(path: string): Promise<string> {
  const content = await Zotero.File.getContentsAsync(path);
  if (typeof content !== "string" && (content as any).responseText) {
    // This happens when getContentsAsync hits the deprecated jar path.
    // The responseText contains the file contents as a string, so
    // this is still usable.
    return (content as any).responseText || "";
  }
  return content as string;
}

// Copies the bundled zotlight/native/ tree to destDir. Uses the build-time
// MANIFEST and Zotero.File.getContentsAsync so it works with both file://
// (dev) and jar: (XPI install) rootURIs.
async function copyNativeDir(destDir: string): Promise<void> {
  // getContentsFromURL uses synchronous XHR which returns responseText as a
  // plain string — works for both file:// (dev) and jar: (XPI) URIs.
  // getContentsAsync must NOT be used here: for jar: URIs it hits a deprecated
  // path that returns an XMLHttpRequest object instead of a string.
  const nativeBase = `${rootURI}zotlight/native/`;
  const manifest = await getContent(`${nativeBase}MANIFEST`);
  for (const line of manifest.split("\n")) {
    const relPath = line.trim();
    if (!relPath) continue;

    const destPath = PathUtils.join(destDir, ...relPath.split("/"));
    const parentDir = PathUtils.parent(destPath);
    if (parentDir) {
      await IOUtils.makeDirectory(parentDir, {
        createAncestors: true,
        ignoreExisting: true,
      });
    }

    const contents = await getContent(`${nativeBase}${relPath}`);
    await IOUtils.writeUTF8(destPath, contents);
  }
}

async function buildAndInstall(): Promise<void> {
  const tmpDir = PathUtils.join(
    PathUtils.tempDir,
    `zotlight-build-${Date.now()}`,
  );

  await copyNativeDir(tmpDir);

  // Ensure shell scripts are executable after the directory copy
  for (const f of ["build.sh", "install.sh", "extract-icon.sh"]) {
    const r = await Zotero.Utilities.Internal.exec("/bin/chmod", [
      "+x",
      PathUtils.join(tmpDir, f),
    ]);
    if (r instanceof Error) throw r;
  }

  // Run install.sh from tmpDir; $1 is passed as a positional arg to avoid
  // quoting issues with special characters in the temp path
  const r = await Zotero.Utilities.Internal.exec("/bin/bash", [
    "-c",
    'export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" && cd "$1" && bash install.sh',
    "--",
    tmpDir,
  ]);
  if (r instanceof Error) throw r;
}
