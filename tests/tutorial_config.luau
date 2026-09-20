-- Run from the repository root: lune run tests/tutorial_config.luau
local TutorialConfig = require("../src/shared/TutorialConfig")

assert(TutorialConfig.OwnerReplayUserId == 1790165114, "RoScapes must use the same owner account as Word Hunt")
assert(TutorialConfig.ShouldStart(true, TutorialConfig.OwnerReplayUserId, false), "owner must replay after completion")
assert(TutorialConfig.ShouldStart(false, 123, false), "new players must receive the tutorial")
assert(not TutorialConfig.ShouldStart(true, 123, false), "completed players must not replay")
assert(TutorialConfig.ShouldStart(true, 123, true), "test override must still work")

print("PASS tutorial owner replay policy")
