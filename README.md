# RoScapes

Roblox Luau source for a Wordscapes-style game with pack progression, daily puzzles, freeplay, timed games, PvP, and hardcore runs.

## Source layout

- `src/server/ServerMain.server.luau`: server entrypoint, remotes, mode orchestration, and purchases.
- `src/server/services`: authoritative gameplay, persistence, economy, and level generation.
- `src/server/Levels` and `src/server/Dictionary`: level templates and word lists.
- `src/client/ClientMain.local.luau`: client entrypoint.
- `src/client`: interface, letter wheel, tutorial, and mode controllers.
- `src/shared`: remote registry, configuration, and shared helpers.

See [AGENTS.md](AGENTS.md) for the project guide and [the initial review](docs/initial-review.md) for findings and verification steps.

## Roblox Studio

This repository contains source scripts. The existing Studio place supplies the HUD, other instances, sounds, and assets; this is not a standalone place export and does not currently include a Rojo project mapping.

Apply source changes to the matching scripts in the existing place, preserving their hierarchy. Server code belongs in a server-only container, shared code is expected at `ReplicatedStorage.Shared`, and `ClientMain.local.luau` must be a client-executed LocalScript with its sibling module folders available. Git pushes do not update the published Roblox experience.

## Private webhook configuration

`ModerationConfig.luau` optionally loads a sibling ModuleScript named `ModerationWebhooksPrivate`. Its local source file, `src/server/services/ModerationWebhooksPrivate.luau`, is excluded from Git. Existing credentials were preserved in that file in the original workspace.

On a fresh checkout, create that private file only if Discord notifications are needed:

```lua
return {
    purchases = "",
    flags = "",
    rejoin = "",
}
```

Set the URLs privately and copy the module alongside `ModerationConfig` in the server-only Studio hierarchy. Without this module, webhook destinations default to empty strings and notifications are skipped. Never put the private module in ReplicatedStorage or commit its contents.

## Checks

With Selene installed, run `selene src`. After restoring the original animations at the owner's request, Selene 0.31.0 reports one error, zero parse errors, and 145 warnings. The error is the original Play-button animation's `Instance.new("Vector2Value")` call. Gameplay and UI verification require the existing place in Studio.

Run `lune run tests/purchases.luau` with Lune 0.10.2 for the purchase persistence and timed reward regression tests. These run the production modules against a simulated datastore and player tree, including failed writes, duplicate receipts, and competing server sessions. See [purchase reliability and deployment](docs/purchase-reliability.md) before applying these changes to Studio.

## Git

The remote is `https://github.com/BeamoDev/RoScapes.git`, with `main` as the working branch. Use `git status` and `git diff` to review changes before committing and pushing. Keep private configuration excluded.
