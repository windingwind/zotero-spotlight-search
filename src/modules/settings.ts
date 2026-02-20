const ZOTLIGHT_APP = "/Applications/ZotLight.app";

export function openConfig(): void {
  ztoolkit.log("[SpotlightSearch] Opening ZotLight settings...");
  // -n forces a new instance even if one is already running
  Zotero.Utilities.Internal.exec("/usr/bin/open", [
    "-n",
    "-a",
    ZOTLIGHT_APP,
  ]).then((r) => {
    if (r instanceof Error)
      ztoolkit.log(`[SpotlightSearch] Failed to open ZotLight settings: ${r}`);
  });
}
