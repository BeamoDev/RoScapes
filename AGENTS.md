# RoScapes Agent Guide

## Project Shape
- Roblox Luau project rooted under `src/`.
- Main entrypoints:
  - `src/server/ServerMain.server.luau`
  - `src/client/ClientMain.local.luau`
  - `src/shared/RemoteRegistry.luau`
- Core code is split into:
  - `src/server/services`: game state, persistence, modes, economy, moderation, analytics
  - `src/server/Levels`: template letter sets and daily content
  - `src/server/Dictionary`: word lists used for required and bonus words
  - `src/client/ui`, `src/client/gameplay`, `src/client/panels`, `src/client/controllers`: HUD, board, wheel, mode flows, tutorial, panels
  - `src/shared/systems`: shared configs and validators

## Gameplay Model
- This is a Wordscapes-style Roblox game with:
  - normal pack progression
  - daily puzzle (`packId = 0`)
  - freeplay (`packId = -1`)
  - timed modes
  - PvP
  - hardcore runs
- The server is authoritative for level content, word validation, rewards, hints, and progression.
- `RemoteRegistry:GetFunction("GetLevelData")` both builds/loads a level and starts the active server session for that player.

## Level Pipeline
- Normal levels start from `src/server/Levels/LevelTemplate.luau`.
- `LevelService` converts template letters into a live board by:
  - collecting possible words from `WordDictionaryService`
  - generating a crossword layout through `CrosswordLayoutService`
  - building client-safe payloads through `LevelPayloadService`
- Important: template keys are sparse and served in sorted order. Missing numeric keys do not create missing playable levels.
- Standard pack levels are generated at runtime, then frozen in `GameService` session state for that player.
- `levelData.words` are the required board words. `levelData.bonus` are valid extra words that should not be required for completion.

## Persistence And State
- `DataService` owns the player schema, migrations, analytics logging, coins, hints, selection hints, quests, achievements, daily state, moderation flags, and rank points.
- If you change persisted fields, update:
  - `defaultData()`
  - `stripDeprecatedKeys()`
  - any folder mirroring or read helpers that expose the value to the client
- Active level state lives in `GameService` sessions. If you add per-run state, keep start/reset/complete flows consistent across normal, daily, timed, PvP, and hardcore modes.

## High-Risk Areas
- Remote changes must stay aligned across `RemoteRegistry`, `ServerMain`, and client callers.
- Hint or reveal changes usually touch:
  - `src/server/services/LevelPayloadService.luau`
  - `src/server/services/GameService.luau`
  - `src/server/ServerMain.server.luau`
  - `src/client/ui/GameBoard.luau`
  - `src/client/gameplay/LetterWheel.luau`
- Economy or purchase changes usually touch:
  - `src/shared/MonetizationConfig.luau`
  - `src/server/ServerMain.server.luau`
  - `src/client/ClientMain.local.luau`
  - `src/client/ui/UIManager.luau`
- Level-progression changes should be checked against `LevelPackConfig`, `LevelService`, `LevelSelect`, and saved progress in `DataService`.

## Working Notes
- Favor server-side fixes over client-only trust.
- Be careful with pack semantics:
  - `packId > 0`: normal progression
  - `packId = 0`: daily
  - `packId = -1`: freeplay
- There is a `selene.toml`, but no obvious automated test harness in this repo snapshot. Expect manual verification in Studio or live-like play flows after gameplay changes.
