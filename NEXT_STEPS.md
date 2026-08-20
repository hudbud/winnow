# Next Steps — Testing & Shipping

## Immediate: Build & Test

1. **Open in Xcode**
   ```bash
   cd /Users/hud/conductor/workspaces/winnow/san-diego/ImageSort
   open ImageSort.xcodeproj  # or generate with xcodegen first
   ```

2. **Build for iPhone**
   - Select "ImageSort" scheme
   - Pick your physical iPhone as destination (NOT simulator for PhotoKit testing)
   - Build (⌘B) and verify no compilation errors

3. **Test the crash fix**
   - If you still have the app installed and it's crashing: DELETE it first
   - Install this new build
   - Should launch successfully now (ratings will be gone but app won't crash)

## On-Device Testing Checklist

Run these tests on your actual iPhone with a real photo library:

### Basic functionality
- [ ] Launch app → album picker appears
- [ ] Select a small album (< 100 photos) → deck loads
- [ ] Swipe 10 cards left and right → smooth, no hitches
- [ ] Tap undo → card comes back
- [ ] Tap skip → card moves to end
- [ ] Complete a pass → review screen appears
- [ ] Tap "Finish Up" → Commit screen appears

### Performance (big album required)
- [ ] Select Recents or an album with 1,000+ photos
- [ ] Time album open: Should be < 2 seconds
- [ ] Time deck push: Should not freeze, shows loading spinner briefly
- [ ] Swipe frame rate: Should stay at 60fps, no jank
- [ ] Complete pass → review grid appears in < 2 seconds
- [ ] Tap "Finish Up" → Commit screen appears instantly (not minutes)

### Memory
- [ ] Swipe through 100+ cards continuously
- [ ] App should not crash (previously would jetsam around 150-200 cards)
- [ ] If you trigger a memory warning (hard to do manually), app should survive

### Edge cases
- [ ] Album with videos → video poster shows, tap play works
- [ ] Album with Live Photos → static shows, tap/autoplay works
- [ ] Dark/light theme toggle → works
- [ ] Rating badge picker → can set manual ratings 1-5
- [ ] VoiceOver enabled → all buttons have labels

## Known Remaining Issues

These were identified in the plan but not fixed (lower priority):

1. **FeedbackService endpoint**: Still points at `https://example.com/...`
   - The feedback-based unlock path will always fail in production
   - Either stand up a real endpoint or gate this feature until you do

2. **Limited photo access**: No "manage selection" affordance
   - If user selects "Limited Photos" permission, they can't expand the set
   - Should show the system sheet via `PHPhotoLibrary.shared().presentLimitedLibraryPicker(from:)`

3. **Video player cleanup**: AVPlayer instances aren't explicitly released
   - Should pause and nil out when card leaves the deck
   - Low severity: viewDidDisappear should clean them up anyway

4. **Auto-resume**: App always starts at album picker
   - PLAN.md says it should resume mid-session if one exists
   - Enhancement, not a bug

## Before TestFlight

1. **Bump build number** in `project.yml` or Xcode
2. **Test migration**:
   - Install previous build from App Store / TestFlight
   - Rate some photos
   - Install THIS build
   - Launch → should not crash, ratings should persist (if we kept the old schema) or be wiped (if migration failed and recovery kicked in)
3. **Archive & upload** to TestFlight
4. **Check Xcode Organizer** after a few test flights go out for any new crash reports

## Instruments Profiling (Optional but Recommended)

Run these before shipping to catch any issues we missed:

```bash
# Time Profiler: check for hot spots in deck/review/commit screens
Instruments → Time Profiler → run on device → swipe 50 cards

# Allocations: check memory growth
Instruments → Allocations → run on device → swipe 100 cards → check "All Heap & Anonymous VM"
# Should stay under 200 MB. If it crosses 300 MB, jetsam risk is high.

# Leaks: check for obvious leaks (Live Photos, video players)
Instruments → Leaks → run through a full pass
```

## Monitoring After Ship

- **Xcode Organizer → Crashes**: Check daily for the first week
- **MetricKit** (optional): Add MXMetricManager to get on-device diagnostics
  - Would catch hangs, jetsams, and crashes even from non-TestFlight users

---

## Quick Reference: What We Fixed

| Issue | Symptom | Fix |
|-------|---------|-----|
| Schema migration crash | App crashes on every launch after update | ModelContainer recovery path |
| Threading violation | Random crashes after album load | @MainActor on view models |
| Giant SQL IN clause | Ratings disappear on 10k+ albums | Fetch all ratings, filter in memory |
| CommitView hang | "Finish Up" screen freezes for minutes | Load ratings once in onAppear |
| Review screen lag | Grid hitches on every tap | Cache filtered assets in @State |
| Deck push freeze | Opening big album hitches navigation | Async VM init with loading state |
| Memory jetsam | App killed after 100-200 swipes | Reduced prefetch 10→5, memory warning handler |
| Animation glitches | Double-animation on fast taps | isCommittingSwipe flag |
| Haptic latency | First swipe feels sluggish | Prepare generator in onAppear |

All changes committed to branch `hudbud/mobile-crash-perf-plan` (commit 1aae1d2).
