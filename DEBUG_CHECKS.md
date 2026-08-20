# Debug Checks — Quick Verification

Run these in Xcode while debugging on device to verify the fixes are working.

## 1. Check Main-Actor Isolation

Set a breakpoint in `AlbumPickerViewModel.loadAlbums` at line 30 (inside the Task), then in the Xcode debug console:

```lldb
(lldb) po Thread.current
```

Should show you're on a background thread for the PhotoKit fetch, then jump to main thread for the state mutation. Before the fix, this was all background and would crash.

## 2. Check Rating Cache Load

Set a breakpoint in `SwipeDeckViewModel.loadRatingCache` at line 108 (after the fetch), then:

```lldb
(lldb) po allRows.count
(lldb) po ratingCache.count
```

Should show reasonable numbers (not 0 if you've rated photos). Before the fix, large albums would show 0 even with ratings.

## 3. Check Prefetch Depth

Set a breakpoint in `SwipeDeckViewModel.prefetch()` at line 313, then:

```lldb
(lldb) po ahead.count
```

Should show 5 (or less if near the end of queue). Before the fix, this was 10.

## 4. Check Memory Warning Handler

While swiping through cards, trigger a simulated memory warning:
- Xcode → Debug → Simulate Memory Warning

Then check the console output — you should see the prefetch cache getting cleared and rebuilt with a smaller window. If the app crashes here, the memory warning handler isn't working.

## 5. Verify Async VM Init

Set a breakpoint in `SwipeDeckView.body` at line 44, then step through. You should see:
1. First render: `viewModel == nil` → ProgressView shows
2. Task starts creating VM
3. Second render: `viewModel != nil` → deckContent shows

Before the fix, there was no loading state and the init blocked.

## 6. Check Commit Screen Performance

Set a breakpoint in `CommitView.loadRatings()` at line 142, then:

```lldb
(lldb) po ratingCache.count
(lldb) po discardedAssets.count  
(lldb) po topTierAssets.count
```

These should populate instantly (single SwiftData fetch). Before the fix, there would be thousands of individual fetches.

## Console Warnings to Watch For

These indicate problems that should NOT appear with the fixes:

❌ `Publishing changes from background threads is not allowed`
→ Main-actor isolation broken

❌ `PhotoLibrary: SQL error: too many SQL variables`  
→ Rating cache fix didn't work

❌ `Memory level: Critical`
→ Memory headroom fix might not be enough

❌ `Could not initialize ModelContainer`
→ Container recovery path didn't work

## Quick Memory Check (no debugger needed)

After swiping 100+ cards:
1. Take note of which photo you're on
2. Backgrounding the app (swipe to home screen)
3. Wait 5 seconds
4. Reopen the app

If the app relaunches at the album picker instead of continuing where you left off, it was jetsam-killed. That means memory pressure is still too high. If it resumes at the same photo, memory fix is working.
