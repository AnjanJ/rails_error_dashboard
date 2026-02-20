# Loading States & Skeleton Screens Design

**Issue:** [#43](https://github.com/AnjanJ/rails_error_dashboard/issues/43)
**Date:** 2026-02-20

## Summary

Add loading indicators and skeleton screens across 5 areas of the dashboard to improve perceived performance and user experience. Uses Stimulus via CDN with a single `LoadingController` and pure CSS skeleton animations.

## Approach: Stimulus + CSS Skeletons

### Stimulus Setup

- Load Stimulus via CDN: `@hotwired/stimulus@3.2.2`
- Register a single `LoadingController` inline in the layout `<script>` block
- Follows existing pattern of inline JS, no build tooling

### CSS Skeleton Animations

Inline CSS classes added to the layout `<style>` block:

- `.skeleton` — Base: shimmer gradient animation (`linear-gradient` with `background-size: 200%`, `@keyframes shimmer`)
- `.skeleton-text` — Text placeholder (`height: 1em; width: 60%`)
- `.skeleton-card` — Stat card placeholder (`height: 80px`)
- `.skeleton-row` — Table row placeholder (`height: 48px`)
- `.skeleton-chart` — Chart area placeholder (`height: 250px`)
- `.loading-spinner` — Wraps Bootstrap spinner for button states
- Dark mode variants adjust gradient colors

All pure CSS, GPU-accelerated via `transform`.

### LoadingController

```
Targets: skeleton, content, submitButton, filterForm

Actions:
  submit(event)  → Filter form submit: show skeletons, hide content, disable button + spinner
  click(event)   → Async button click: disable button, show spinner
  connect()      → Listen for turbo:before-stream-render, turbo:frame-load to auto-hide skeletons
  disconnect()   → Cleanup event listeners

Safety: 10s timeout auto-restores UI if response never arrives
```

## Implementation Areas

### 1. Dashboard Stats (index.html.erb)
- 4 skeleton card placeholders with `.skeleton-card`, hidden by default
- Wrapped in `data-loading-target="skeleton"`
- Existing stat cards wrapped in `data-loading-target="content"`
- Skeletons show on filter submit

### 2. Error List (index.html.erb)
- 5 skeleton table rows with `.skeleton-row`
- Wrapped in `data-loading-target="skeleton"`
- Existing `_error_row` partials wrapped in `data-loading-target="content"`
- Skeletons show during filter application

### 3. Charts (index.html.erb + analytics.html.erb)
- `.skeleton-chart` placeholder divs next to chart containers
- Show until Chart.js renders (MutationObserver or Chart.js callback)

### 4. Filters (index.html.erb)
- `data-action="submit->loading#submit"` on filter form
- Submit button: spinner + disabled during submission
- Filter inputs: disabled during loading

### 5. Async Action Buttons (show.html.erb)
- Resolve, Assign, Priority, Snooze modal submit buttons: `data-action="click->loading#click"`
- Button text replaced with spinner, button disabled on click
- `button_to` actions (unassign, unsnooze) get same treatment

## When Skeletons Appear

Skeletons appear only on filter/refresh actions, not initial page load. Initial page load shows real server-rendered content immediately.

## Testing

- System tests (Capybara): verify skeleton elements exist, correct CSS classes, button disabled states
- No chaos test changes needed (purely frontend)
- Manual verification: `HEADLESS=false bundle exec rspec spec/system/`
