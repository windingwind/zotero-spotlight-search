export function registerPreferencePane(): void {
  Zotero.PreferencePanes.register({
    id: "spotlightSearch",
    pluginID: addon.data.config.addonID,
    src: "content/preferences.xhtml",
  });
}
