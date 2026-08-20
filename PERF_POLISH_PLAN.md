# ImageSort — Crash, Performance & Polish Plan

Ordered by priority. P0 items are crash-on-launch candidates; P1 are measurable
performance problems; P2 is feel/polish; P3 is how we verify it all.

## P0 — Fix the launch crash

### 0.1 Confirm the crash with a real log (do this first)
On the phone: Settings → Privacy & Security → Analytics & Improvements →
Analytics Data → look for `ImageSort-*.ips` entries. Or plug in and use
Xcode → Window → Devices and Simulators → View Device Logs. Everything below
is ranked by likelihood, but 5 minutes with the actual log beats guessing.

### 0.2 `try!` ModelContainer + schema drift  ← prime suspect
`ImageSortApp.swift:9` force-unwraps container creation. The schema has
demonstrably changed across builds (`ReviewedAsset.swift` says it *replaced* a
`[String]` array on `Session`; `Session.sortStatusRaw` was also added later).
A device that installed an older build has an old SwiftData store on disk;
lightweight migration fails → `try!` traps → **crash on every launch until the
app is deleted**. This exactly matches "every time I open it, it crashes."

Fix:
- Adopt `VersionedSchema` + `SchemaMigrationPlan` so future model changes
  migrate deliberately.
- Wrap container creation in a recovery path: on failure, move the store file
  aside and create a fresh container (losing ratings beats a permanent crash
  loop), and log/report that it happened.
- Quick user-side confirmation: deleting the app from the phone and
  reinstalling should stop the crash if this is the cause.

### 0.3 ModelContext + @Observable mutated off the main actor
`AlbumPickerViewModel.loadAlbums` (AlbumPickerViewModel.swift:27) runs
`Task { ... }` from a non-isolated class, so the body executes on a background
executor — it then calls `context.fetch(...)` on the main-actor-bound
`ModelContext` and mutates `albums` / `isLoading` / `sessionsByAlbumID`
(observed by SwiftUI) off-main. This is undefined behavior that can crash
right after the album list appears — the other launch-path suspect.

Fix: annotate `AlbumPickerViewModel` (and `SwipeDeckViewModel`) `@MainActor`;
keep only the pure PhotoKit fetch in `Task.detached`. Same treatment for
`EntitlementStore` (mutates observable state from background tasks in `init`).

### 0.4 Giant `IN` predicate can silently drop all ratings
`SwipeDeckViewModel.loadRatingCache` (SwipeDeckViewModel.swift:99) builds
`#Predicate { identifiers.contains(...) }` from *every asset in the album*.
For a big album (Recents, 10–50k) this compiles to an enormous SQL `IN`
clause that can exceed SQLite limits; the `try?` swallows the failure and the
app proceeds with an **empty rating cache** — mid-session ratings appear lost
and pass semantics break. Fix: fetch all `PhotoRating` rows (the table is
small — one row per rated photo) and filter against the identifier set in
memory; or batch the predicate in chunks of ~500.

## P1 — Performance

### 1.1 CommitView issues one SQL query per photo, per render
`CommitView.rating(_:)` (CommitView.swift:19) does a `FetchDescriptor` fetch
for a single identifier, and `discardedAssets` / `topTierAssets` /
`assetsAtOrAbove` filter `allAssets` calling it per element — **from computed
properties evaluated in `body`**. A 5,000-photo album means tens of thousands
of SQLite round-trips every render; the Finish Up screen will hang for
seconds-to-minutes and can get the app watchdog-killed. Fix: load one
`[String: Int]` rating dictionary in `onAppear` (or reuse the deck VM's
cache) and compute the three groups once, storing them in `@State`.

### 1.2 EndOfPassReviewView re-filters the whole album per body eval
`filteredAssets` (EndOfPassReviewView.swift:32) and `viewModel.survivors`
(each an O(n) filter over `allAssets` with a rating lookup per element) are
computed properties read multiple times per `body` evaluation — and `body`
re-evaluates on every tap-to-toggle with animation. Fix: compute once into
`@State`, invalidate on `displayThreshold` change and on toggle (the toggle
only moves one asset — update incrementally).

### 1.3 Deck view model built synchronously during navigation push
`SwipeDeckView.init` (SwipeDeckView.swift:33) constructs
`SwipeDeckViewModel`, whose init does the SwiftData fetch (0.4) plus two full
O(n) filters over the album — on the main thread, mid-navigation-transition.
Big albums hitch or freeze the push. Fix: give the deck a lightweight loading
state and build queue/caches async.

### 1.4 Image memory headroom (jetsam = "it crashed")
`cardTargetSize` is full-screen pixels (~12–15 MB decoded per image on a 3×
device) and the VM prefetches 10 ahead → ~150 MB+ of decoded images plus
PhotoKit's own overhead. Under memory pressure iOS jetsams the app, which
users experience as a crash. Fix:
- Drop prefetch depth to ~5 (still far ahead of swiping speed).
- Handle `UIApplication.didReceiveMemoryWarningNotification`: call
  `stopCachingAll()` and re-prefetch a shorter window.
- Replace deprecated `UIScreen.main` sizing with the window scene's bounds.

### 1.5 Album list, minor
- `displayedAlbums` filters + sorts in `body` on every eval — memoize on
  (albums, filter, sortOption).
- `AlbumRow` thumbnail requests are never cancelled on fast scroll; fine for
  dozens of albums, worth a `PHImageRequestID` cancel in `onDisappear` if the
  list grows.

## P2 — Polish

- **Fly-out race** (SwipeDeckView.swift:311): `DispatchQueue.asyncAfter` to
  finish a swipe races with fast repeated swipes/taps — cards can glitch or
  double-animate. Drive completion off the animation (`withAnimation(...)
  completion:` is available on iOS 17) and ignore input while a fly-out is in
  flight.
- **Live Photo continuation leak** (PhotoLibraryService.swift:170): if the
  request errors without a non-degraded delivery, the continuation never
  resumes and the Task leaks. Resume on error/nil too; support cancellation.
- **Video cards**: pause/release the `AVPlayer` when the card leaves the deck;
  today playback state relies solely on view teardown.
- **Limited-library auth**: PLAN.md calls for surfacing the "manage selection"
  affordance under `.limited`; currently it's treated the same as full access.
- **FeedbackService placeholder**: endpoint is `https://example.com/...` — the
  feedback half of the unlock path always fails in production. Stand up the
  endpoint or gate the soft-ask path off until it exists.
- **Haptics**: create/`prepare()` one `UIImpactFeedbackGenerator` instead of
  allocating per swipe (avoids first-tap latency).
- **Accessibility**: labels for icon-only buttons (undo, skip, theme, Live
  Photo toggle), and VoiceOver actions for keep/pass so the deck is usable
  without the drag gesture.
- **Resume affordance**: opening the app mid-session lands on the album
  picker; consider auto-resuming the active session (PLAN: "resume from
  persisted Session position").

## P3 — Verify

1. **Migration test**: install the previous build, create ratings, then
   install the new build over it — must launch and keep data.
2. **Big-album test**: run on-device against Recents (10k+): album open time,
   deck push time, swipe frame rate, Finish Up screen render time.
3. **Instruments**: Time Profiler on deck + review + commit screens;
   Allocations/memory graph while swiping 100+ cards (watch for jetsam
   territory, >300 MB).
4. **Crash visibility going forward**: check Xcode Organizer crash reports;
   consider MetricKit hooks so the next field crash isn't a mystery.

## Suggested order of work

1. 0.1 read the crash log → 0.2 container recovery + migration plan (small,
   likely fixes "crashes every time")
2. 0.3 main-actor isolation for the two view models + EntitlementStore
3. 0.4 rating-cache fetch rewrite
4. 1.1 CommitView + 1.2 review screen (biggest perceived-perf wins)
5. 1.4 memory headroom, 1.3 async deck load
6. P2 polish items, roughly in listed order
7. P3 verification pass on-device
