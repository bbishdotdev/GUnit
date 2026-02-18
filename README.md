# G-Unit

Guild-shared PvP hit list tracker for WoW TBC Classic.

Track enemy players your guild wants dead, coordinate bounties, and automatically detect kills via the combat log.

## Features

- **Shared hit list** — Add targets and sync across guild members using addon-to-addon chat.
- **Auto-detection** — Kills, target sightings (mouseover, target, nameplate), and location tracking happen automatically.
- **Bounties** — Set gold bounties with one-time or indefinite payout modes. Mark kills as claimed/paid.
- **Kill on Sight (KOS)** — Mark targets as KOS (persistent) or one-time (auto-completes after first kill).
- **Import/Export** — Bulk share your hit list via semicolon-delimited text.
- **Guild sync** — `/gunit sync` to pull the full hit list from online guild members running the addon.

## Installation

1. Download or unzip `GUnit` so you have a folder named `GUnit` containing the `.toc` and `.lua` files.
2. Copy the `GUnit` folder into your WoW addons directory:

```
World of Warcraft\_classic_\Interface\AddOns\GUnit\
```

The final structure should look like:

```
World of Warcraft/
  _classic_/
    Interface/
      AddOns/
        GUnit/
          GUnit.toc
          Core.lua
          Utils.lua
          HitList.lua
          Comm.lua
          Sync.lua
          BountyTrade.lua
          Tracking.lua
          Tooltip.lua
          UITheme.lua
          UIComponents.lua
          UI.lua
          Commands.lua
```

3. Restart WoW (or `/reload` if already in-game).
4. On the character select screen, click **AddOns** and make sure **G-Unit** is enabled.

> **Note:** All guild members who want to share the hit list need the addon installed. Targets, kills, and bounty changes are synced via hidden addon messages over guild chat.

## Usage

| Command | Description |
|---|---|
| `/gunit` | Toggle the main UI window |
| `/ghit` | Add your current target to the hit list |
| `/ghit remove <name>` | Remove a target |
| `/ghit reason <name> <text>` | Set/update the reason for a hit |
| `/ghit bounty <name> <gold>` | Set a bounty amount (in gold) |
| `/ghit mode <name> <one-time\|kos>` | Set hit mode |
| `/ghit bounty-mode <name> <none\|first\|infinite>` | Set bounty payout mode |
| `/ghit complete <name>` | Mark a hit as completed |
| `/ghit reopen <name>` | Re-open a completed hit |
| `/gunit sync` | Request a full sync from online guild members |
| `/gunit export` | Open the export window |
| `/gunit import` | Open the import window |

You can also use `/g-unit` as an alias for `/gunit`.

## Testing Checklist

Use this to validate the addon is working correctly in-game.

### Basic Setup
- [ ] Addon loads without Lua errors on login
- [ ] `/gunit` opens the main UI window
- [ ] Window is draggable and stays on screen

### Adding Targets
- [ ] Target an enemy player and type `/ghit` — target appears in the list
- [ ] Class icon, race icon, and faction icon display correctly on the new entry
- [ ] Adding a target with `/ghit` while no player is targeted shows an error message

### Detail Drawer
- [ ] Click a target in the list — detail drawer slides open on the right
- [ ] Name, class, race, faction, status, bounty, and kill count display correctly
- [ ] "Last Seen" location updates when you target/mouseover a tracked player
- [ ] Close button (X) closes the drawer

### Edit Mode (Submitter Only)
- [ ] "Edit" button appears only on targets you submitted
- [ ] Clicking "Edit" shows editable fields: reason, hit mode dropdown, bounty amount, bounty mode dropdown
- [ ] Kill Details section remains visible in edit mode
- [ ] Changing values and clicking "Save" persists changes
- [ ] Going back to readonly mode restores all fields correctly
- [ ] Kill details section is still visible after save (not disappearing)

### Kill Tracking
- [ ] Kill an enemy player on the hit list — kill count increments
- [ ] One-time hits auto-complete after the first kill
- [ ] KOS hits stay active after kills
- [ ] Kill details table shows killer name, last kill time, kill count
- [ ] Guild message is sent on kill ("X has been killed!")

### Bounties
- [ ] Set a bounty amount and mode (one-time or indefinite) via edit mode
- [ ] After a kill, the killer's "Claimed" column shows a checkmark
- [ ] In edit mode, the "Paid" column is clickable for claimed kills
- [ ] Clicking paid toggles between checkmark and X
- [ ] Submitter's own kills show X for both claimed and paid (ineligible)

### Sync & Communication
- [ ] `/gunit sync` sends a sync request (check that a guild member with the addon responds)
- [ ] Adding/editing/removing a target broadcasts to guild members with the addon
- [ ] Changes from other guild members appear without reloading

### Import/Export
- [ ] `/gunit export` shows the export window with semicolon-delimited data
- [ ] Copy the export text, clear list, then `/gunit import` and paste — data restores
- [ ] Imported targets show correct class, race, faction, and location data

### Settings
- [ ] Settings panel accessible from the UI
- [ ] Default hit mode, bounty amount, and bounty mode apply to new targets
- [ ] Guild announcement toggle works (on/off)

## Known Limitations

- Export does not include individual kill records or bounty claim/payment history (only kill count and target metadata are exported).
- Bounty payments via trade window require both players to have the addon installed.
- The addon communicates over guild addon channel — only guild members with G-Unit installed will see updates.
