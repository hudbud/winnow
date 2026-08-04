# ImageSort — iOS photo culling app

Tinder-style swipe interface for progressively rating photos from an Apple Photos album, modeled on Lightroom-style multi-pass culling. Native iOS app, no backend, no accounts.

## Stack

- SwiftUI, iOS 17+, Xcode project
- PhotoKit for library access (`PHAsset`, `PHAssetCollection`, `PHCachingImageManager`)
- SwiftData for local persistence
- No network services of any kind

## Core constraint

iOS PhotoKit has **no star-rating API**. Ratings live entirely in the app's own SwiftData store, keyed by asset `localIdentifier`. The photo library is never modified by swiping — only by explicit user actions: the "Create album" CTA on end-of-pass review screens, and the Commit step at the end (albums / favorites / delete).

## Data model

- `Session` — selected album's collection identifier, current pass number, current position in queue, created/updated timestamps. One active session at a time (v1).
- `PhotoRating` — asset `localIdentifier`, rating `Int` 0–5, updated timestamp. **Unrated (no row) is distinct from rating 0** — 0 means explicitly discarded in pass 0.

Ratings persist across launches; a large album can be culled over multiple days. Sessions resume mid-pass at the saved position.

## Pass semantics (exact — do not change)

Rating scale: 0 = discard, 1–5 = keep tiers. Passes are numbered N = 0, 1, 2, 3, 4.

- **Queue for pass N**: all assets in the album with rating ≥ N, in capture-date order. Pass 0's queue additionally includes all unrated assets.
- **Swipe right**: rating = `max(current, N + 1)`. So an unrated or N-rated photo promotes to N+1, but a photo already rated 3 encountered during the 0→1 pass **stays 3** — never bumped to 4.
- **Swipe left**: if current rating > N, **unchanged**; otherwise rating = N. In pass 0, left on an unrated photo sets it to 0 (discard).
- Net effect: photos rated above the current pass flow through the deck untouched in either direction. A pass can only ever promote from ≤ N to exactly N+1, and can never demote anything above N. Promotion is idempotent (right sets rating *to* N+1, never increments).
- **Swipe down** (or skip button): defer — re-queue the card at the end of the current pass, rating unchanged.
- **Undo button**: rewinds the last swipe — restores both the previous rating and the deck position. Maintain an undo stack for the whole pass, not just one step.

Re-culling/demoting an already-rated tier is explicitly **out of scope for v1** (would be a separate deliberate mode, never a side effect of a keep pass).

## Screen flow

1. **Permission + album picker** — request `PHPhotoLibrary` `.readWrite` auth. List user albums and relevant smart albums (Recents, Favorites) with cover thumbnail and asset count. Selecting one creates/resumes a `Session`.
2. **Swipe deck (pass N)** — card stack:
   - Drag gesture with translation + slight rotation; commit past a threshold, spring back otherwise.
   - Overlay stamps while dragging: green "KEEP" (right), red "PASS" (left).
   - Haptic on commit.
   - Progress indicator for position within the pass (e.g. thin bar or "142 / 1,840").
   - Undo button.
   - **Rating badge** on every card, always visible in a corner:
     - Unrated (pass 0): no badge or hollow star — absence signals "your swipe decides."
     - Rated: "★N".
     - When card rating > current pass N: dim/tint the badge differently so it reads as "locked — already past this round" (the swipe is decorative, not decisive). Without this cue the app feels like it's ignoring input.
3. **End-of-pass review** — shown when the queue is exhausted:
   - Count summary, e.g. "212 of 1,840 kept."
   - Thumbnail grid of survivors (rating ≥ N+1), reusing the same badge component. Tap a thumbnail to toggle its fate (promote/demote across the N/N+1 boundary only) — cheaper than re-swiping to fix one mistake.
   - **Primary CTA: "Create album"** — creates a real Apple Photos album containing the current survivors (rating ≥ N+1) via `PHAssetCollectionChangeRequest`. This is the app's core outcome and must be available at the end of *every* pass, not only after the final one — the user decides when the set is tight enough. Default album name suggests source + tier (e.g. "Japan Trip — Picks ★2+"), editable before creating. If run again after further refinement, offer update-in-place (sync album contents to current survivors) vs. create-new.
   - Secondary actions: **"Refine further →"** (start pass N+1) or **"Done"** (go to Commit for the remaining options).
4. **Commit screen** — final cleanup step. Independent, user-checkable actions:
   - Create/update albums per tier (e.g. "★3+", "★5") — bulk variant of the review screen's Create album CTA, for materializing multiple tiers at once.
   - Mark top tier as system Favorites.
   - Delete all 0-rated via `PHAssetChangeRequest.deleteAssets` (moves to Recently Deleted; iOS presents its own confirmation dialog). Discards are otherwise never touched — swiping must feel consequence-free.

## Image pipeline

- `PHCachingImageManager`, prefetch ~10 assets ahead of the deck position; stop caching behind.
- Request degraded thumbnail first, swap in full quality when it arrives.
- `isNetworkAccessAllowed = true` for iCloud-only originals; show progress on slow fetches.
- Videos: show as muted autoplaying card. Live Photos: static with a Live badge.

## Edge cases

- New photos added to the album mid-session: ignored until a new session (pass 0 re-run will pick them up as unrated).
- Assets deleted from the library out from under the app: prune orphaned `PhotoRating` rows when building a queue; never crash on a missing asset.
- Interruption/kill mid-pass: resume from persisted `Session` position.
- Limited-library authorization: respect the limited selection; surface the "manage selection" affordance.

## Milestones (build in order)

1. **Scaffold + library access** — project setup, permission flow, album picker with counts and covers.
2. **Swipe deck** — the card stack, gestures, stamps, haptics, badge. This is the feel of the whole app; tune it properly (spring response, drag thresholds, rotation amount).
3. **Rating store + pass engine** — SwiftData models, exact pass semantics above, resume, undo stack.
4. **End-of-pass review** — counts, grid, tap-to-toggle, advance to next pass.
5. **Commit actions** — albums per tier, favorites, delete 0-rated.
6. **Polish** — video/Live Photo cards, dark UI (photos read better on black), progress bar, animations.

## Style notes

- Dark UI throughout; the photo is the hero, chrome stays minimal.
- No settings screen in v1. Local-only, no sync, no iPad-specific layout.
