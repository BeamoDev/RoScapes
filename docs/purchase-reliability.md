# Purchase reliability and timed rewards

Timed mode now awards 13 base coins per server-confirmed solved puzzle, followed by the existing rank multiplier. `FinishTimedMode` ignores all extra client arguments and consumes the active match before awarding anything. Client callers no longer send win flags or solved counts. Word submissions received after the server deadline are rejected. Normal clients previously sent `false`, so their normal finish payout is preserved.

## Purchase processing

- `PurchaseRewards` resolves every configured product, including special hints whose original purchase prompt or board is gone.
- `DataService` records `PurchaseId -> ProductId` in a server-only `processedReceipts` map. Rewards and that map are saved together in the existing `Wordscapes_v2` profile using `UpdateAsync`.
- Receipt acknowledgement requires a confirmed saved snapshot containing that receipt. Failed saves return `NotProcessedYet`; the staged reward is not added again on retry. A concurrent autosave only confirms receipts present in its own snapshot.
- `ReceiptProcessor` prevents simultaneous handling of the same receipt. Feedback failures cannot turn a durably granted purchase into another grant.
- Coin purchase analytics and client currency updates remain supported.
- Receipt history is retained without pruning and is not mirrored into player folders or returned by `GetPlayerData`.

Special hints first save a normal inventory hint as a fallback. If the original prompted session still exists, the current handler can reveal the requested cell or row and consume that hint. Otherwise the inventory hint remains available. This follows the previous one-hint fallback for unavailable special actions and now also handles delayed receipts after reconnecting. Transient reveals are not themselves permanent profile inventory: if a server dies after revealing but before saving the hint deduction, the saved fallback hint can remain. The durable receipt still prevents granting another purchase reward on redelivery.

## Save ownership and loading

`ProfilePersistence` acquires an expiring `_session` ownership token with `UpdateAsync` when loading. Another updated server cannot load the same profile while the lease is live. Saves verify ownership atomically, so an expired server cannot overwrite a newer session. Each successful save renews the ten-minute lease; the existing autosave interval remains three minutes.

Normal departures and `BindToClose` attempt a final save and release ownership, including profiles already in `PlayerRemoving`. A crashed server's unreleased lease can prevent loading for up to ten minutes. Failed loads or malformed profiles no longer become writable default profiles; the player is asked to rejoin instead. Existing table and JSON-string profiles are still accepted, using the existing datastore name and keys.

## Validation

`lune run tests/purchases.luau` passes 18 tests covering:

- Existing profile migration, failed/corrupt loads, ownership exclusion, lease expiry, and stale writes.
- Every configured product's reward, receipt deduplication, write failures, lost write acknowledgements, retries after spending, overlapping autosaves, and rejoining the same or a different server.
- Unknown products, absent player data, concurrent duplicate delivery, feedback exceptions, and persisted special-hint fallback.
- Forged timed-mode arguments, repeated finish requests against the actual handler, and Luau compilation of changed entrypoints.

These tests use a simulated datastore and player tree, not live Roblox services. Source lint still includes the previously restored Play-button animation error; this change does not modify animations.

## Applying to Roblox

1. Copy all changed scripts and the four new server modules (`ProfilePersistence`, `PurchaseRewards`, `ReceiptProcessor`, and `TimedRewards`) into the matching Studio hierarchy. Keep them server-only.
2. Use a separate test experience/datastore to check a normal purchase, a bundle, daily/PvP hints, reconnecting, and timed-mode completion. Verify inventory remains correct after leaving and rejoining.
3. Publish the scripts together and restart existing servers during rollout. Old server builds still use `SetAsync` and do not respect the new ownership tokens; leaving those builds running can defeat the new safeguards. Do not roll back to that old save implementation while new sessions are active.

GitHub synchronization does not publish the Roblox place. No live purchases or production datastore writes were performed during these tests. This change cannot reconstruct previously lost or duplicated purchase grants.

Implementation references: [Roblox developer products](https://create.roblox.com/docs/production/monetization/developer-products), [UpdateAsync](https://create.roblox.com/docs/reference/engine/classes/GlobalDataStore#UpdateAsync).
