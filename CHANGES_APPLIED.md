# ImageSort Performance & Crash Fixes — Applied Changes

## P0 — Crash Fixes ✅

### 1. ModelContainer crash recovery (ImageSortApp.swift)
- **Problem**: `try!` force-unwrap would crash on schema migration failures
- **Fix**: Wrapped in do-catch with recovery path that moves corrupt store aside and creates fresh container
- **Impact**: App now recovers from schema drift instead of permanent crash loop

### 2. Main-actor isolation (ViewModels + EntitlementStore)
- **Problem**: Observable state mutated and ModelContext accessed from background threads
- **Fix**: Added `@MainActor` to:
  - `AlbumPickerViewModel`
  - `SwipeDeckViewModel`
  - `EntitlementStore`
- **Fix**: Wrapped state mutations in `MainActor.run` in `AlbumPickerViewModel.loadAlbums`
- **Impact**: Eliminates undefined behavior that could crash during album load

### 3. Rating cache fetch for large albums (SwipeDeckViewModel.swift)
- **Problem**: Giant SQL IN clause from 10k+ asset IDs would exceed SQLite limits and silently fail
- **Fix**: Fetch ALL PhotoRating rows (small table), filter in memory against album asset set
- **Impact**: Ratings won't mysteriously disappear on big albums

## P1 — Performance Fixes ✅

### 1. CommitView O(n²) database access (CommitView.swift)
- **Problem**: `rating()` helper ran one fetch per photo, called from computed properties in `body`
- **Fix**: Load all ratings once in `onAppear` into `@State var ratingCache`, compute filtered groups once
- **Impact**: Finish Up screen loads instantly instead of hanging for minutes on large albums

### 2. EndOfPassReviewView re-filtering (EndOfPassReviewView.swift)
- **Problem**: `filteredAssets` computed property evaluated multiple times per body render
- **Fix**: Moved to `@State`, recompute only on `displayThreshold` change or toggle
- **Impact**: Review grid no longer hitches on every interaction

### 3. Async deck view model initialization (SwipeDeckView.swift + SwipeDeckViewModel.swift)
- **Problem**: SwiftData fetch + queue rebuild blocked navigation push on main thread
- **Fix**: 
  - Made VM init private, added `static func create()` async factory
  - SwipeDeckView starts with loading state, builds VM in Task
- **Impact**: Opening big albums no longer freezes the push animation

### 4. Memory headroom (PhotoLibraryService.swift + SwipeDeckViewModel.swift)
- **Problem**: 10 prefetched full-screen 3× images = ~150 MB, risking jetsam
- **Fix**:
  - Reduced prefetch depth from 10 to 5
  - Added `handleMemoryWarning()` to drop cache and re-prefetch
  - SwipeDeckView listens for `didReceiveMemoryWarningNotification`
  - Replaced deprecated `UIScreen.main` with window scene bounds
- **Impact**: Lower memory footprint, less likely to be killed under pressure

## P2 — Polish Fixes ✅

### 1. Fly-out animation race (SwipeDeckView.swift)
- **Problem**: Fast repeated taps could trigger overlapping animations
- **Fix**: Added `isCommittingSwipe` flag, disable buttons during fly-out
- **Impact**: No more glitchy double-animations

### 2. Live Photo continuation leak (PhotoLibraryService.swift)
- **Problem**: If request errored without non-degraded delivery, continuation never resumed
- **Fix**: Also resume on error to prevent Task leak
- **Impact**: No leaked tasks on Live Photo load failures

### 3. Haptic latency (SwipeDeckView.swift)
- **Problem**: Allocating UIImpactFeedbackGenerator per swipe caused first-tap delay
- **Fix**: Create one generator as stored property, `prepare()` in `onAppear`
- **Impact**: Haptics feel snappier

### 4. Accessibility labels (SwipeDeckView.swift)
- **Fix**: Added `.accessibilityLabel()` to all icon-only buttons:
  - Undo, Live Photo toggle, theme toggle
  - Back/skip navigation buttons
  - Keep/pass action buttons
- **Impact**: VoiceOver users can now understand what each button does

## Not Yet Implemented (Would Require More Work)

- **Limited-library affordance**: Showing "manage selection" UI under `.limited` auth
- **FeedbackService endpoint**: Still points at `example.com` placeholder
- **Video player cleanup**: Pause/release AVPlayer when card leaves deck
- **Auto-resume session**: Opening mid-session still lands on album picker

## Testing Checklist

Before shipping to TestFlight:

1. **Migration test**: Install old build, create ratings, install new build over it → must launch
2. **Big-album test**: On-device with Recents (10k+):
   - Album open time
   - Deck push time
   - Swipe frame rate (should stay at 60fps)
   - Finish Up screen render time (should be instant)
3. **Memory test**: Instruments → Allocations, swipe 100+ cards, watch for jetsam territory (>300 MB)
4. **Crash log**: Check Xcode Organizer after first TestFlight build goes out

## Files Modified

- `ImageSort/Sources/App/ImageSortApp.swift`
- `ImageSort/Sources/Services/PhotoLibraryService.swift`
- `ImageSort/Sources/Services/EntitlementStore.swift`
- `ImageSort/Sources/ViewModels/AlbumPickerViewModel.swift`
- `ImageSort/Sources/ViewModels/SwipeDeckViewModel.swift`
- `ImageSort/Sources/Views/SwipeDeckView.swift`
- `ImageSort/Sources/Views/EndOfPassReviewView.swift`
- `ImageSort/Sources/Views/CommitView.swift`
