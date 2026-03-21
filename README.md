# LucidUI

A complete chat replacement, loot tracking, session statistics and quality-of-life addon for World of Warcraft (Retail).

![Interface](https://img.shields.io/badge/Interface-12.0.x-blue)
![Version](https://img.shields.io/badge/Version-1.0-green)

---

## Features

### Chat System
Replaces WoW's default chat with a fully custom interface.

- **Tabbed chat** with up to 10 configurable tabs and whisper highlighting
- **Custom message display** with timestamps, class-colored names, and vertical separators
- **Clickable URLs** detected automatically in chat messages
- **Message fade** with configurable timeout
- **Copy chat** window for easy text export
- **Chat bar** with quick-access buttons (Social, Settings, Copy, Rolls, Stats, Voice Chat)
- **Hyperlink tooltips** for items, spells, achievements, keystones and more

### Loot Tracker
A dedicated loot feed in its own window or as a chat tab.

- Real-time loot logging with item quality filtering
- Group loot with class-colored player names
- Gold / Silver / Copper tracking
- Option to show only your own drops
- Realm name display toggle

### Loot Rolls
Tracks group loot rolls in a separate window.

- Live roll tracking with item icons and player names
- Boss filter dropdown
- Minimum quality filter
- Auto-close timer or manual close mode

### Session Statistics
Per-session tracking for dungeons and raids.

- Boss kills, deaths, looted items, gold earned
- Zone and instance tracking
- Session history with archival
- One-click reset

### Quality of Life

| Feature | Description |
|---|---|
| **Combat Timer** | On-screen combat duration display |
| **Combat Alert** | Visual enter/exit combat notifications |
| **Mouse Ring** | Cursor ring overlay with multiple shapes and colors |
| **Auto Vendor** | Auto-sell grey items, auto-repair (guild bank or personal) |
| **Faster Loot** | Instant loot pickup |
| **Skip Cinematics** | Auto-skip cutscenes and movies |
| **Suppress Warnings** | Auto-confirm BoP, disenchant and trade dialogs |
| **Auto Keystone** | Automatically pick up keystones |
| **FPS Optimizer** | One-click graphics reduction with backup & restore |

### Theming
- **Default dark theme** with cyan accents
- **Fully custom theme** — window frame, border, titlebar, text, brackets and icon colors
- Per-element transparency controls

---

## Slash Commands

| Command | Action |
|---|---|
| `/lucid` `/lui` `/lu` | Open settings |
| `/lucid reset` | Reset all settings to defaults |

---

## Installation

1. Download or clone this repository
2. Copy the `LucidUI` folder into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
3. Restart WoW or type `/reload`

---

## Localization

LucidUI auto-detects your WoW client language. Supported languages:

- English (default)
- Deutsch
- Fran&ccedil;ais
- Italiano
- Espa&ntilde;ol
- Portugu&ecirc;s (BR)
- Русский
- 한국어
- 简体中文
- 繁體中文

Missing translations fall back to English automatically.

---

## Project Structure

```
LucidUI/
├── Locales.lua          # Auto-detected localization
├── Core.lua             # Namespace, constants, database, themes
├── Options.lua          # Main settings window (4 tabs)
├── HyperlinkHandler.xml
├── Chat/
│   ├── ChatFrame.lua    # Chat window, tabs, editbox, event hooking
│   ├── ChatFormat.lua   # Timestamps, class colors, URLs, channel shortening
│   ├── ChatMessageArea.lua  # Custom slot-based message display
│   ├── ChatComponents.lua   # Reusable UI components
│   ├── ChatBar.lua      # Vertical button bar
│   ├── ChatOptions.lua  # Chat settings dialog (7 tabs)
│   └── Messages.lua     # Message storage, history, formatting
├── Loot/
│   ├── LootTracker.lua  # Main loot window, events, slash commands
│   ├── LootHandlers.lua # CHAT_MSG_LOOT / CHAT_MSG_MONEY processing
│   ├── LootRolls.lua    # Loot roll tracking window
│   └── SessionStats.lua # Session statistics tracking
├── QoL/
│   ├── Main.lua         # QoL initialization
│   ├── CombatTimer.lua  # Combat duration timer
│   ├── CombatAlert.lua  # Combat enter/exit alerts
│   ├── MouseRing.lua    # Cursor ring overlay
│   ├── AutoVendor.lua   # Auto-repair & auto-sell
│   ├── SkipCinematics.lua
│   ├── SystemOpt.lua    # FPS optimizer
│   └── Misc.lua         # Faster loot, suppress warnings, auto keystone
├── Debug/
│   └── Main.lua         # Debug log window
└── Assets/              # Icons, textures, sounds
```

---

## License

This project is licensed under the [MIT License](LICENSE).
