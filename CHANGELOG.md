# Changelog

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
