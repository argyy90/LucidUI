# LucidUI

A comprehensive UI addon for World of Warcraft (Retail) featuring a cooldown manager, custom chat, bags, damage meter, loot tracking, resource bars, cast bar, trinket/item tracking, gold tracking, Mythic+ tracking and quality-of-life features.

![Interface](https://img.shields.io/badge/Interface-12.0.x-blue)
![Version](https://img.shields.io/badge/Version-1.19-green)

---

## Features

### Chat System
Replaces WoW's default chat with a fully custom interface.

- **Tabbed chat** with up to 10 configurable tabs, all tabs including Tab 1 can be renamed
- **Custom message display** with timestamps, class-colored names, and vertical separators
- **Clickable URLs** detected automatically in chat messages
- **Message fade** with configurable timeout
- **Copy chat** window for easy text export
- **Chat bar** with quick-access buttons (Social, Settings, Copy, Rolls, Stats, Voice Chat)
- **Hyperlink tooltips** for items, spells, achievements, keystones and more
- **Combat-safe input** — typing works correctly during combat without taint issues

### LucidMeter — Damage Meter
A built-in damage meter powered by the native `C_DamageMeter` API (WoW 12.x+).

- **10 meter types** — Damage Done, DPS, Healing Done, HPS, Absorbs, Interrupts, Dispels, Damage Taken, Avoidable Damage, Deaths
- **Multiple windows** — open as many meter windows as you need, each with its own meter type and session
- **Snap system** — drag windows to snap them together edge-to-edge (Details-style), they move and resize as a group
- **Session selector** — switch between Current, Overall, and any saved combat session per window
- **Proportional bar fill during combat** — bars scale correctly relative to each other even with tainted secret values
- **Spell breakdown tooltip** — hover over any player to see a per-spell breakdown with amounts, DPS and percentages
- **Report Results** — send results to Say, Party, Raid, Instance, Guild or Whisper with configurable line count
- **Class colors** and **spec/class icons** on each bar
- **Auto reset** on entering or leaving instances
- **Fully themeable** — bar texture, bar height, spacing, font, transparency, accent line, borders and more

### Loot Tracker
A dedicated loot feed in its own window or as a chat tab.

- Real-time loot logging with item quality filtering
- Group loot with class-colored player names
- Gold / Silver / Copper tracking
- Option to show only your own drops
- Realm name display toggle

### Loot Rolls
Tracks group loot rolls in a separate window. Redesigned with full cyberpunk aesthetic.

- Live roll tracking with item icons and player names
- **Quality-colored left accent bar** per item card
- **PCB circuit trace background decoration**
- Boss filter dropdown
- Minimum quality filter
- Auto-close timer or manual close mode

### Session Statistics
Per-session tracking for dungeons and raids. Redesigned with cyberpunk window style.

- Boss kills, deaths, looted items, gold earned
- Zone and instance tracking
- Session history with archival — history rows styled with accent bars and corner decorations
- **PCB circuit trace background** in all windows
- One-click reset

### Gold Tracker
A complete trade and gold tracking module.

- **Automatic trade logging** — every completed trade is recorded with items given and received
- **Trade history window** with dual-column YOU GAVE / YOU RECEIVED layout
- **Net gold per trade** with color-coded positive/negative totals
- **Gold Flow graph** — dual-bar chart (gave vs received) per day with hover tooltips
- **7d / 14d / 30d** range selector on the inline settings graph
- **Session overview** in the settings tab — total trades, gold received, gold given, net gold
- **Whisper on trade complete** — optional summary whisper to your trade partner
- **Export CSV** — export your full trade history as a spreadsheet
- **PCB circuit trace background** decoration

### Mythic+ Tracker
A full-featured Mythic+ run tracker matching GLogger's feature set.

- **Automatic run tracking** — records every Mythic+ run with dungeon, key level, time, status, deaths, roster and loot
- **Blizzard history sync** — imports existing runs from `C_MythicPlus.GetRunHistory` and `GetSeasonBestForMap` on login
- **Season mapping** — correctly maps Blizzard's varying API season IDs (Midnight Season 1)
- **Season migration** — automatically moves runs from old season buckets to the correct season on login
- **1150×700px tracker window** with:
  - **M+ Rating** — overall score in Blizzard's rarity color
  - **Dungeon tile row** — 8 tiles with textures, best key level and score per dungeon, click to filter
  - **Players pane** — teammate analytics sorted by last seen, click to filter runs
  - **Run History table** — sortable by date (newest first), dungeon, level, time, status and deaths; trophy icon for season-best runs
  - **Run Details panel** — score, date, time/limit, deaths+time-lost, affixes with icons, roster with role icons and class colors, loot with trade tracking
  - **Key Level Chart** — fixed-width bars grouped by dungeon with hover tooltips, scrollable
  - **Delete Run** with confirmation popup
  - **Sync Blizzard** and **Clear All** buttons
  - Mask Names and Hide Fails checkboxes
- **Settings tab** with season overview stats and inline key level chart
- **PCB circuit trace background** decoration
- **Live accent color updates** — all window elements update instantly when accent color changes

### LucidCDM — Cooldown Manager
Hooks into Blizzard's CooldownViewer system to restyle and reposition cooldown frames.

- **Essential & Utility Cooldowns** — custom icon size, spacing, per-row count, grow direction
- **Cast Bar** — custom width, height, textures, colors (cast/channel/failed/uninterruptible), class color option, spell name and timer display
- **Resource Bars** — primary + secondary resource support with automatic class/spec detection, partial resource fill (Soul Shards), segmented pips, optional mana bar with auto-detection for healer specs
- **Buff Icons & Buff Bars** — custom icon size, bar width/height, grow direction, duration text, stack count, border textures
- **Trinkets & Racials** — two separate bars for trinket slots and custom items (healthstones, potions), anchored to player unitframe with offset sliders, cooldown text, stack count, grow direction
- **Auto Width** — resource and cast bars automatically match Essential Cooldowns width
- **Anchor Chain** — stacked positioning: Cooldowns → Resources → CastBar → BuffIcons → BuffBars
- **Combat-safe** — `SetPreventSecretValues`, viewer reparenting, raw proxy SetPoint hooks prevent taint
- **Class Layouts** — per-class CooldownViewer layouts imported during install wizard (13 classes)
- **Spec Change handling** — automatic refresh and re-reparenting on talent/spec changes
- **Edit Mode integration** — lock overlay prevents accidental Edit Mode repositioning
- **`/cdm` command** — toggle Blizzard's CooldownViewer settings window

### LucidBags — Custom Bags
Replaces WoW's default bag frames with a clean, customizable inventory.

- **Configurable grid** — icon size, spacing, columns
- **Item Level display** with position and font size options
- **Quality borders** — colored borders by item quality
- **Junk detection** — coin icon on junk items, optional desaturation
- **Quest & Upgrade icons** — quest exclamation mark, upgrade arrows
- **Stack count** with position and font size options
- **New item glow** — gold pulse on freshly looted items
- **Reverse slot order** and **transparent slots** options
- **Separate reagent bag** window
- **Split individual bags** with configurable gap
- **Slot opacity** slider
- **Item ID in tooltip** — shown on all item tooltips via TooltipDataProcessor
- **Auto-open** at bank, mailbox, auction house, merchant, trade
- **Hide default bag bar** option

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

### Theming & UI Style
- **Cyberpunk dark aesthetic** across all windows — dark backgrounds, accent bars, corner cuts, staircase decorations
- **PCB circuit trace backgrounds** — interlocking horizontal/vertical trace patterns with glowing nodes, visible in the settings window, Gold Tracker, Mythic+ Tracker, Loot Rolls, Session Stats and Session History
- **Live accent color updates** — change the accent color in settings and all open windows update instantly without reload
- **Default dark theme** with cyan accents
- **Fully custom theme** — window frame, border, titlebar, text, brackets and icon colors
- Per-element transparency controls

---

## Slash Commands

| Command | Action |
|---|---|
| `/lucid` `/lui` `/lu` | Open settings |
| `/lucid reset` | Reset all settings to defaults |
| `/lucid install` | Re-run the install wizard |
| `/cdm` | Toggle Blizzard CooldownViewer settings |

---

## Installation

1. Download or clone this repository
2. Copy the `LucidUI` folder into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
3. Restart WoW or type `/reload`
4. The **Install Wizard** will appear on first login:
   - **Step 1** — Select resolution (1440p / 1080p) for optimal sizing
   - **Step 2** — Choose which modules to enable
   - **Step 3** — Apply class-specific cooldown layout (auto-detected)
   - **Step 4** — Review and reload

All modules are disabled by default. Use the wizard or `/lui` settings to enable them.

---

## Localization

LucidUI auto-detects your WoW client language. Supported languages:

- English (default)
- Deutsch
- Français
- Italiano
- Español
- Português (BR)
- Русский
- 한국어
- 简体中文
- 繁體中文

Missing translations fall back to English automatically.

---

## Credits

- **[GLogger (Gold Logger)](https://www.curseforge.com/wow/addons/glogger)** by Osiris the Kiwi — licensed under GPLv3.
  Portions of this project (`Mythicplus/MythicPlus.lua`, `GoldTracker/GoldTracker.lua`) are derived from GLogger.

- **SalesTools** — Original authors of the code GLogger was built upon:
  - Emily Cohen / Emilýp-Illidan
  - Honorax-Illidan
  - David Martínez / Volthemar-Dalaran

---

## License

This project is licensed under the [GNU GPL v3.0.](LICENSE)