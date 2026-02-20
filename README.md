# Zotero Spotlight Search

[![zotero target version](https://img.shields.io/badge/Zotero-8,9-green?style=flat-square&logo=zotero&logoColor=CC2936)](https://www.zotero.org)
[![macOS only](https://img.shields.io/badge/macOS-only-lightgrey?style=flat-square&logo=apple)](https://www.apple.com/macos/)

Search your Zotero library directly from macOS Spotlight.

## How it works

This plugin integrates Zotero library with macOS Spotlight Search. Search your library and groups in Spotlight even when Zotero is not running.

You can customize how the items are formatted in the search results.

The index is updated incrementally when your library changes. No background activities.

## Setup

1. Install the plugin (`.xpi`) in Zotero via **Tools → Plugins**
2. ZotLight.app is installed automatically in the background on first launch
   > For macOS restrictions, we must use an app to index the Zotero with Spotlight database. The app is built from source at runtime, see `native/` for details.
3. Open **ZotLight.app Settings…** from Zotero **Preferences → Spotlight Search** to configure which fields to index

Your Zotero items will appear in Spotlight results shortly after.

## Settings

- Install / Update ZotLight.app
- Open ZotLight Settings
- Uninstall ZotLight.app

## Requirements

macOS only. Test on macOS Tahoe 26.2.

## License

AGPL3
