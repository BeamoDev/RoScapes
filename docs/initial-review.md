# Initial source review

## Player report: hint button keeps jumping

The complaint describes a deliberate attention animation in `HomeHud.StartHintButtonPulse`. After a 3.2-second delay it enlarged the button's scale by 10%, rotated it between +4 and -4 degrees, and flashed a green outline. The animation and its extra wait made it repeat roughly every 4.8 seconds while the button was on screen, outside the tutorial.

Removed the animation loop, its startup call, and its unused visibility helper and import. The hint count badge, normal hover/click feedback, tutorial guidance, and server hint handling remain available. The complaint did not require changing hint prices, rewards, or saved data.

## Other fixes

| Finding | Change |
| --- | --- |
| Controller Y-button callback referenced `shuffleLetters` before its local declaration, resolving it as an undefined global. | Forward-declared the local function variable before input callbacks. |
| Daily selected-cell hints called `isWordCell` before its local declaration. | Moved the helper above its first caller. |
| Group reward tutorial checks referenced `tutorialSessionActive` before its local declaration. | Moved the session flag beside the other tutorial state. |
| Home Play-button pulse attempted to create `Vector2Value` and assign a Vector2 to `UIStroke.BorderOffset`. | Tween the stroke directly using UDim offsets, matching the [Roblox API](https://create.roblox.com/docs/reference/engine/classes/UIStroke#BorderOffset). |
| An old `ShowHintShop` implementation referenced an undefined `hintsLabel`; another implementation replaced that method later in the same module. | Removed only the superseded method, retaining the active shop and pack configuration. |
| Two consecutive level target branches returned the same target. | Combined the ranges without changing level targets. |
| Discord webhook credentials were embedded in source intended for a public repository. | Moved credentials into an ignored, optional server-only module before the initial Git commit. |

## Architecture observations

The game separates client presentation from server gameplay services. Runtime boards derive from letter templates and dictionaries; `GameService` holds active sessions and `DataService` owns persistent player data. Hint requests are handled on the server and branch by mode. No remote contracts or persistence schema were changed in this review.

The repository is a scripts-only snapshot. UI assets and a reproducible Studio/Rojo mapping are not included. This review traced the reported behavior and static diagnostics; it is not a complete gameplay, security, or purchase audit.

## Validation

- Selene 0.31.0 before changes: 7 errors, 146 warnings, no reported parse errors.
- After changes: 0 errors, 145 warnings, 0 parse errors. Existing warnings mainly concern unused variables, formatting, shadowing, and simplifications.
- `git diff --check` passed.
- Confirmed no remaining source references to the removed idle hint pulse.
- Verified private webhook configuration is ignored and checked staged content for common credential patterns before publication.
- Studio gameplay was not run in this environment.

## Studio verification before publishing

1. Enter a normal puzzle and leave the pointer away from Hint for at least 30 seconds. The hint button should remain still. Repeat after returning home and starting another puzzle, and in daily, freeplay, timed, and PvP modes.
2. Use a hint and verify the reveal and hint count update. Check zero-hint behavior and the hardcore restriction.
3. Run onboarding with a test account. Confirm the hint step still guides the player and group reward prompts respect tutorial activity.
4. Use controller Y to shuffle and check the tutorial shuffle callback. Confirm hardcore still rejects shuffling.
5. In an appropriate purchase test environment, exercise a daily selected-cell hint and confirm a valid cell is revealed without an undefined-function error.
6. Check the home Play-button outline animation and the hint shop balance display. Monitor Studio Output for errors.
7. Preserve the private webhook module in the server-only hierarchy when applying the updated moderation configuration.

Publish the Studio place only after these checks. GitHub synchronization alone does not publish the game.
