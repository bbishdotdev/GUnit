# Changelog

## v0.5.0

### Fixed
- **Submitter corruption during partial sync** — metadata/location packets no longer overwrite valid submitters with `Unknown` when `submitter` is absent.
- **Last seen location corruption on sync** — core/meta sync packets no longer fabricate location from local defaults; location updates only apply when explicit `lastSeen*` fields are present.
- **Reason wipe protection** — blank reason payloads no longer overwrite existing reasons unless sent as an explicit clear with a newer reason timestamp.
- **Debug mode default regression** — startup now normalizes persisted settings so debug logging is only enabled when `debugMode` is literal `true`.

### Changed
- **Reason protocol hardening** — `REASON` messages now carry `reasonUpdatedAt` and explicit clear intent (`reasonClear`) for non-destructive merges.
- Addon metadata version bumped to `0.5.0` in both runtime (`Core.lua`) and TOC (`GUnit.toc`).

---

## v0.4.1

### Added
- **Party chat announcements** — hit added, called off, target spotted nearby, engagement, and kill events now broadcast to party chat alongside guild chat
- **Party announcements setting** — toggle in Settings > General to enable/disable party broadcasts independently from guild announcements
- `/gunit guildies` command — lists all known addon users in your guild with last-seen timestamps
- `Utils.RelativeTime()` helper for human-readable time formatting

### Fixed
- **Guildie counter robustness** — self-registration now re-fires on `GUILD_ROSTER_UPDATE` to fix nil guild name from early login; counter cross-references the guild roster to prune ex-guildies
- **CLI remove missing guild announcement** — `/ghit remove` now announces "called off" to guild chat (was local print only)
- **Import/export semicolon corruption** — field values containing `;` or `%` are now escaped in exports and unescaped on import, preventing field misalignment

### Changed
- Guild roster is proactively requested on login so roster data is available for addon user validation

---

## v0.4.0

### Fixed
- **Guild sync completely broken** — all target data messages (UPSERT, SYNC_DATA, SYNC_PUSH) exceeded WoW TBC Classic's 255-byte addon message limit and were silently dropped. Guild chat announcements worked but no target data ever reached other guild members.
- **Sync deadlock** — if a sync responder disconnected mid-transfer, `isSyncing` stayed true forever, blocking all future sync attempts until relog

### Changed
- **New wire protocol (v1)** — compact 1-2 character wire keys replace verbose field names, reducing message size by ~60%
- **Field group splitting** — target data split into Core (~130b), Meta (~80b), Location (~160b), and Reason (~170b) messages. Each group is well under the 245-byte limit regardless of data content.
- **Reason sent as separate message** — reason text gets its own 245-byte budget (~175 chars). Self-sufficient: carries submitter/guild so it can create stub targets if needed.
- **Flat sync encoding** — sync entries encoded in a single pass instead of nested encoding that doubled payload size from separator escaping

### Added
- Debug logging toggle (`/gunit debug` or Options checkbox) for sync diagnostics — logs every sent/received message with size and status
- `/gunit stats` command — session counters for sent, dropped, and received messages by action type
- Protocol version tag (`v=1`) on all outbound messages for future evolution
- 15-second watchdog timer on sync claims to prevent deadlocks
- `HitList:EnsureAndSetReason()` for self-sufficient reason handling
- `SYNC.md` — full protocol reference documentation

---

## v0.3.0

### Added
- Addon icon/logo displayed in WoW addon list (clients that support `## IconTexture`)
- Kill details section now visible in edit mode — submitters can mark bounties as paid without leaving edit mode

### Changed
- Hit list now sorted by newest first (descending by date added) instead of alphabetical

### Fixed
- Kill details section disappearing after toggling between edit and readonly mode (circular anchor dependency)

---

## v0.2.0 — Initial Release

First public release of G-Unit for TBC Classic.

### Features

- **Shared hit list** — Add enemy players to a guild-wide hit list via `/ghit` or the UI
- **Detail drawer** — Click any target to view class, race, faction, location, status, bounty, and kill history
- **Edit mode** — Submitters can edit reason, hit mode, bounty amount, and bounty mode inline
- **Kill tracking** — Automatic kill detection via combat log with per-killer breakdown
- **Bounty system** — Set gold bounties with one-time or indefinite payout modes
- **Bounty claims** — Kills auto-claim bounties; submitters can mark kills as paid in edit mode
- **Kill on Sight (KOS)** — Persistent hit mode that stays active across multiple kills
- **One-time hits** — Auto-complete after the first confirmed kill
- **Target sighting alerts** — Get notified when a tracked enemy is spotted (target, mouseover, nameplate)
- **Last seen location** — Tracks zone, subzone, and coordinates of most recent sighting
- **Guild sync** — Full hit list sync between online guild members via `/gunit sync`
- **Addon chat broadcast** — All changes (add, edit, remove, kill) broadcast to guildies with the addon
- **Bounty trade detection** — Recognizes gold trades as bounty payments between addon users
- **Import/Export** — Bulk share hit lists via semicolon-delimited text
- **Slash commands** — Full CLI via `/gunit` and `/ghit` for all operations
- **Class/race/faction icons** — Visual identification in both the list and detail views
- **Configurable defaults** — Set default hit mode, bounty amount, and bounty mode for new targets
- **Guild announcements** — Optional auto-announce to guild chat on kills and bounty updates
- **Tooltip integration** — Hit list targets flagged in unit tooltips
