import { initLocale } from "./utils/locale";
import { createZToolkit } from "./utils/ztoolkit";
import { checkAndInstall, uninstall } from "./modules/install";
import { openConfig } from "./modules/settings";
import {
  registerNotifier,
  scheduleSync,
  unregisterNotifier,
} from "./modules/sync";
import { registerPreferencePane } from "./modules/preferencePane";

async function onStartup() {
  await Promise.all([
    Zotero.initializationPromise,
    Zotero.unlockPromise,
    Zotero.uiReadyPromise,
  ]);

  addon.data.ztoolkit = createZToolkit();

  initLocale();
  registerNotifier();
  registerPreferencePane();

  await Promise.all(
    Zotero.getMainWindows().map((win) => onMainWindowLoad(win)),
  );

  addon.data.initialized = true;

  checkAndInstall({ silent: true }).catch((e) =>
    ztoolkit.log(`[SpotlightSearch] ZotLight check failed: ${e}`),
  );
}

async function onMainWindowLoad(_win: _ZoteroTypes.MainWindow): Promise<void> {}

async function onMainWindowUnload(_win: Window): Promise<void> {}

function onShutdown(): void {
  unregisterNotifier();
  addon.data.alive = false;
  // @ts-expect-error - Plugin instance is not typed
  delete Zotero[addon.data.config.addonInstance];
}

async function onNotify(
  event: string,
  type: string,
  _ids: Array<string | number>,
  _extraData: Record<string, unknown>,
) {
  // Duplicates the notifier in onStartup; kept here for scaffold test coverage.
  if (type === "item" && ["add", "modify", "trash", "delete"].includes(event)) {
    scheduleSync();
  }
}

async function onPrefsEvent(type: string, _data: Record<string, unknown>) {
  if (type === "install") {
    checkAndInstall();
  } else if (type === "openConfig") {
    openConfig();
  } else if (type === "uninstall") {
    const confirmed = Services.prompt.confirm(
      // @ts-expect-error - Services.prompt is not typed
      null,
      "Uninstall ZotLight",
      "This will remove ZotLight.app and its LaunchAgent. Continue?",
    );
    if (confirmed) uninstall();
  }
}

export default {
  onStartup,
  onShutdown,
  onMainWindowLoad,
  onMainWindowUnload,
  onNotify,
  onPrefsEvent,
};
