# G-Unit Sync & Communication Protocol

Reference doc for the addon's wire protocol, sync lifecycle, and known limitations.

## Wire Protocol

All messages use WoW's `C_ChatInfo.SendAddonMessage` on the `GUILD` channel with prefix `GUNIT`.

**Hard constraint:** 255 bytes per message (TBC Classic). Payload budget is **245 bytes** after safety margin.

### Encoding

Messages use flat key-value encoding with compact wire keys:

- Pair separator: `\031` (US)
- Key-value separator: `\029` (GS)
- Values are escaped via `Utils.Escape` (handles `%`, `\029`, `\031`)
- All messages are single-level (no nested encoding)

Full key names are mapped to 1-2 character wire keys:

| Full Key | Wire | Field Group |
|---|---|---|
| action | a | all |
| version | v | all |
| name | n | all |
| submitter | s | core / reason |
| guildName | g | core / reason |
| updatedAt | ua | all |
| createdAt | ca | core |
| hitMode | hm | core |
| hitStatus | hs | core |
| bountyMode | bm | core |
| bountyStatus | bs | core |
| bountyAmount | ba | core |
| validated | vl | core |
| killCount | kc | core |
| classToken | ct | meta |
| race | rc | meta |
| raceId | ri | meta |
| sex | sx | meta |
| faction | f | meta |
| lastSeenMapId | lm | location |
| lastSeenZone | lz | location |
| lastSeenSubzone | ls | location |
| lastSeenX | lx | location |
| lastSeenY | ly | location |
| lastSeenApproximate | la | location |
| lastSeenConfidenceYards | lc | location |
| lastSeenAt | lt | location |
| lastSeenSource | lo | location |
| reason | r | reason |
| killer | kl | kill |
| zone | kz | kill |
| ts | kt | kill |
| mapId | km | kill |
| subzone | ks | kill |
| approximate | ka | kill |
| confidenceYards | ky | kill |
| source | kr | kill |
| requestId | rq | sync control |
| responder | rp | sync control |

### Field Group Splitting

Target data is split across up to 4 separate messages to stay under the 245-byte limit. Each field group is a self-contained message using the same action type (UPSERT, SYNC_DATA, or SYNC_PUSH). The receiver merges them via `UpsertFromComm`, which uses merge semantics (`payload.field or target.field or default`).

| Group | Fields | Sent When | Est. Size |
|---|---|---|---|
| **Core** | name, submitter, guild, modes, statuses, bounty, validated, killCount, timestamps | Always | ~130b |
| **Meta** | name, classToken, race, raceId, sex, faction | Target has class/race/faction data | ~80b |
| **Location** | name, zone, subzone, coords, mapId, source, seenAt, approximate, confidence | Target has location data | ~120-160b |
| **Reason** | name, submitter, guild, reason (uses REASON action) | On reason changes + during sync for all targets | ~70-170b |

A new unvalidated target with no sighting sends only Core + Reason (2 messages). A fully loaded target sends all 4 groups.

### Omit Rules

**Always sent** (can be reverted to defaults or must propagate zero state):
`hitMode`, `hitStatus`, `bountyMode`, `bountyStatus`, `bountyAmount`, `killCount`, `validated`, `lastSeenApproximate`

**Omit when empty** (additive metadata, only grows):
Location fields (`lm`, `lz`, `ls`, `lx`, `ly`, `lc`, `lt`, `lo`), identity metadata (`ct`, `rc`, `ri`, `sx`, `f`)

### Protocol Version

All outbound messages carry `v=1`. Future protocol changes increment this value. The decoder passes through unknown keys for forward compatibility.

## Message Types

### UPSERT (field groups)

Target data without reason. Sent as 1-3 messages depending on which field groups have data:

**Core** (~130b):
```
a=UPSERT, v=1, n=<name>, s=<submitter>, g=<guild>, hm=<hitMode>, hs=<hitStatus>,
bm=<bountyMode>, bs=<bountyStatus>, ba=<amount>, ca=<created>, ua=<updated>
```

**Meta** (~80b, only if class/race/faction present):
```
a=UPSERT, v=1, n=<name>, ct=<class>, rc=<race>, ri=<raceId>, sx=<sex>, f=<faction>, ua=<updated>
```

**Location** (~120-160b, only if location present):
```
a=UPSERT, v=1, n=<name>, lm=<mapId>, lz=<zone>, ls=<subzone>, lx=<x>, ly=<y>,
la=<approx>, lc=<confidence>, lt=<seenAt>, lo=<source>, ua=<updated>
```

All three share the same `updatedAt` timestamp. `UpsertFromComm` merges each partial update correctly because missing fields fall back to existing values.

### REASON

Self-sufficient reason message. Carries `submitter` and `guildName` so it can create a stub target via `EnsureAndSetReason` if the target doesn't exist yet.

```
a=REASON, v=1, n=<name>, s=<submitter>, g=<guild>, r=<reason>, ua=<timestamp>
```

~70 bytes overhead, ~175 chars budget for reason text. Sent on reason changes only (including explicit clear to empty string). During sync, sent for ALL targets to repair missed clears.

### DELETE

```
a=DELETE, v=1, n=<name>, ua=<timestamp>
```

### KILL

```
a=KILL, v=1, n=<name>, kl=<killer>, kz=<zone>, kt=<timestamp>, km=<mapId>,
ks=<subzone>, ka=<approx>, ky=<confidence>, kr=<source>
```

### Sync Control Messages

| Action | Purpose | Size |
|---|---|---|
| SYNC_REQUEST | Request full data from guild | ~60b |
| SYNC_CLAIM | Claim a sync request (random 0-3s backoff) | ~80b |
| SYNC_DATA | Target field group (1-3 per target + requestId) | ~80-160b each |
| SYNC_DONE | All entries + reasons sent | ~60b |
| SYNC_PUSH | Push own data back (1-3 per target) | ~80-160b each |
| SYNC_PUSH_DONE | Push complete | ~40b |

Sync control messages (REQUEST, CLAIM, DONE, PUSH_DONE) use `ActionPayload` with full key names since they're small. Data messages (SYNC_DATA, SYNC_PUSH) use `CompactEncode` with wire keys.

## Sync Lifecycle

```
Requester                          Responder
    |                                  |
    |--- SYNC_REQUEST ---------------->|
    |                                  | (random 0-3s backoff)
    |<-------------- SYNC_CLAIM -------|
    |                                  |
    |    [watchdog: 15s timeout]       |
    |                                  |
    |<--- SYNC_DATA (tgt 1 core) -----|  \
    |<--- SYNC_DATA (tgt 1 meta) -----|   } 0.2s delay between each
    |<--- SYNC_DATA (tgt 1 loc)  -----|  /
    |<--- SYNC_DATA (tgt 2 core) -----|
    |<--- SYNC_DATA (tgt 2 meta) -----|
    |<--- SYNC_DATA (tgt 2 loc)  -----|
    |<--- REASON (tgt 1) -------------|  \
    |<--- REASON (tgt 2) -------------|   } all targets, including empty
    |<--- SYNC_DONE ------------------|
    |                                  |
    | (1s delay)                       |
    |                                  |
    |--- SYNC_PUSH (tgt 1 core) ----->|
    |--- SYNC_PUSH (tgt 1 meta) ----->|
    |--- SYNC_PUSH (tgt 1 loc)  ----->|
    |--- SYNC_PUSH (tgt 2 core) ----->|
    |--- SYNC_PUSH (tgt 2 meta) ----->|
    |--- SYNC_PUSH (tgt 2 loc)  ----->|
    |--- REASON (tgt 1) ------------->|  all targets, including empty
    |--- REASON (tgt 2) ------------->|
    |--- SYNC_PUSH_DONE ------------->|
```

### Auto-sync

Triggers 3 seconds after `PLAYER_LOGIN` if in a guild.

### Manual sync

`/gunit sync` — sends a new SYNC_REQUEST.

### Retry Logic

If no SYNC_CLAIM within 8 seconds, retries once. If still no claim after another 8 seconds, gives up and calls `FinishSync`.

### Deadlock Protection

After receiving SYNC_CLAIM, a 15-second watchdog timer starts. If SYNC_DONE doesn't arrive within that window (e.g. responder disconnects mid-sync), `isSyncing` is forced to `false` so future syncs are not blocked.

### RequestId Format

Format: `<epoch_timestamp>-<random_4digit>` (e.g. `1771224853-4821`). Unique per sync session. Included in SYNC_DATA messages so responder can correlate entries to a request.

## Real-Time Broadcast Flow

When a target is modified outside of sync:

| Event | Messages Sent |
|---|---|
| Target created | UPSERT core + REASON |
| Target validated (unit seen) | UPSERT core + UPSERT meta + UPSERT location |
| Target sighted (combat log) | UPSERT core + UPSERT location |
| Reason changed | UPSERT core + REASON |
| Mode/bounty/status changed | UPSERT core |
| Kill detected | KILL + UPSERT core (+ meta/location if present) |
| Target deleted | DELETE |

`BroadcastReason` is called explicitly by callers that mutate reason (add target, set reason, edit save). Callers that don't touch reason (bounty, mode, status, kill events) only send UPSERT.

## Known Limitations

### Oversize field groups

With field group splitting, each message is well under 245 bytes for all realistic WoW data. If a single field group somehow exceeds the limit (would require pathologically long names), it is dropped with a warning via `CheckedSend`.

**Recovery path:**
1. `/gunit sync` — retry; a different responder may have different data
2. `/gunit export` on the source client, `/gunit import` on the receiving client

### Reason length limit

REASON messages have ~175 characters of budget. Reasons exceeding this are dropped with a warning. The full reason stays in the sender's local database but won't propagate to peers.

### Message ordering

The protocol assumes WoW guarantees message ordering per sender on the GUILD channel. Field groups for the same target arrive in order (core, then meta, then location). REASON messages for all targets arrive after SYNC_DATA entries and before SYNC_DONE.

If ordering is violated (not expected), `UpsertFromComm` merge semantics and REASON's self-sufficient `EnsureAndSetReason` prevent data loss.

## Observability

### Debug mode

Toggle via:
- `/gunit debug` command (persists across sessions)
- Checkbox in G-Unit Options > "Debug logging (sync diagnostics)"

When on, prints gray `[G-Unit DBG]` messages:

| Event | Format |
|---|---|
| Message sent | `SENT <label> (<size>b)` |
| Message dropped | `DROPPED <label> (<size>b) — oversize` |
| Message received | `RECV <action> from <sender> (<size>b) [<target>]` |
| Reason received | `RX REASON for <name> (<len> chars)` |
| Sync requested | `SYNC requested, id=<requestId>` |
| Sync claimed | `SYNC claimed by <responder>` |
| Sync entry received | `SYNC entry received: <name>` |
| Sync done | `SYNC done, pushing own data` |
| Sync finished | `SYNC finished` |
| Watchdog fired | `SYNC watchdog: no SYNC_DONE, forcing finish` |

### Stats

`/gunit stats` — prints session counters:
- `Sent` — total messages successfully sent (across all message types)
- `Dropped` — total messages dropped due to oversize
- `Received` — breakdown by action type (e.g. `UPSERT=12, REASON=4, SYNC_DATA=8`)
