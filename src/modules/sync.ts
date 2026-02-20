const ZOTLIGHT_BINARY = "/Applications/ZotLight.app/Contents/MacOS/ZotLight";

let syncTimer: ReturnType<typeof setTimeout> | null = null;

export function registerNotifier(): void {
  addon.data.notifierID = Zotero.Notifier.registerObserver(
    {
      notify(
        event: string,
        type: string,
        _ids: Array<string | number>,
        _extraData: Record<string, unknown>,
      ) {
        if (
          type === "item" &&
          ["add", "modify", "trash", "delete"].includes(event)
        ) {
          scheduleSync();
        }
      },
    },
    ["item"],
    addon.data.config.addonRef,
  );
}

export function unregisterNotifier(): void {
  if (addon.data.notifierID) {
    Zotero.Notifier.unregisterObserver(addon.data.notifierID);
    addon.data.notifierID = undefined;
  }
}

export function scheduleSync(): void {
  if (syncTimer !== null) {
    clearTimeout(syncTimer);
  }
  syncTimer = setTimeout(() => {
    syncTimer = null;
    sync();
  }, 2000);
}

export function sync(): void {
  ztoolkit.log("[SpotlightSearch] Triggering ZotLight sync...");
  Zotero.Utilities.Internal.exec(ZOTLIGHT_BINARY, ["--sync"]).then((r) => {
    if (r instanceof Error)
      ztoolkit.log(`[SpotlightSearch] ZotLight sync failed: ${r}`);
  });
}
