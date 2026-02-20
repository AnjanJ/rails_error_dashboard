# Loading States & Skeleton Screens Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add loading indicators and skeleton screens across 5 dashboard areas to improve perceived performance and UX.

**Architecture:** Stimulus via CDN with a single inline `LoadingController`. Pure CSS skeleton animations (shimmer gradient). Skeletons shown on filter/refresh only, not initial page load. 10s safety timeout.

**Tech Stack:** Stimulus 3.2.2 (CDN), CSS animations, Bootstrap spinners, existing Chartkick/Chart.js

---

### Task 1: Add Skeleton CSS to Layout

**Files:**
- Modify: `app/views/layouts/rails_error_dashboard.html.erb` (inside `<style>` block, before closing `</style>` tag at line 1323)

**Step 1: Add skeleton CSS classes**

Add the following CSS just before the closing `</style>` tag (line 1323):

```css
/* Skeleton Loading Animations */
@keyframes shimmer {
  0% { background-position: -200% 0; }
  100% { background-position: 200% 0; }
}

.skeleton {
  background: linear-gradient(90deg, #e5e7eb 25%, #f3f4f6 50%, #e5e7eb 75%);
  background-size: 200% 100%;
  animation: shimmer 1.5s ease-in-out infinite;
  border-radius: 4px;
}

body.dark-mode .skeleton {
  background: linear-gradient(90deg, #313244 25%, #45475a 50%, #313244 75%);
  background-size: 200% 100%;
}

.skeleton-text {
  height: 1em;
  width: 60%;
  margin-bottom: 0.5em;
}

.skeleton-text-short {
  width: 40%;
}

.skeleton-card {
  height: 80px;
}

.skeleton-row {
  height: 48px;
  margin-bottom: 2px;
}

.skeleton-chart {
  height: 250px;
}

/* Hide skeleton containers by default */
.loading-skeleton {
  display: none;
}

/* Loading spinner for buttons */
.btn .loading-spinner {
  display: inline-block;
  width: 1em;
  height: 1em;
  border: 2px solid currentColor;
  border-right-color: transparent;
  border-radius: 50%;
  animation: spinner-border 0.75s linear infinite;
  vertical-align: middle;
  margin-right: 0.25em;
}
```

**Step 2: Verify the CSS renders**

Run: `bundle exec rspec spec/system/error_workflow_spec.rb --fail-fast`
Expected: PASS (no regressions from CSS-only changes)

**Step 3: Commit**

```bash
git add app/views/layouts/rails_error_dashboard.html.erb
git commit -m "feat: add skeleton loading CSS animations to layout (#43)"
```

---

### Task 2: Add Stimulus via CDN and LoadingController

**Files:**
- Modify: `app/views/layouts/rails_error_dashboard.html.erb` (add Stimulus CDN script tag + inline controller)

**Step 1: Add Stimulus CDN and LoadingController**

Add the Stimulus CDN script tag after the Bootstrap JS script tag (after line 1567). Then add the LoadingController inline:

```html
<!-- Stimulus (for loading state management) -->
<script src="https://cdn.jsdelivr.net/npm/@hotwired/stimulus@3.2.2/dist/stimulus.min.js"></script>

<!-- Loading State Controller -->
<script>
(function() {
  'use strict';
  if (typeof Stimulus === 'undefined') return;

  var application = Stimulus.Application.start();

  application.register('loading', class extends Stimulus.Controller {
    static get targets() {
      return ['skeleton', 'content', 'submitButton'];
    }

    connect() {
      this._boundHideSkeletons = this.hideSkeletons.bind(this);
      document.addEventListener('turbo:before-stream-render', this._boundHideSkeletons);
      document.addEventListener('turbo:load', this._boundHideSkeletons);
    }

    disconnect() {
      document.removeEventListener('turbo:before-stream-render', this._boundHideSkeletons);
      document.removeEventListener('turbo:load', this._boundHideSkeletons);
      if (this._safetyTimeout) clearTimeout(this._safetyTimeout);
    }

    // Called on filter form submit
    submit() {
      this.showSkeletons();
      this.disableSubmitButtons();
      this.startSafetyTimeout();
    }

    // Called on async action button click
    click(event) {
      var button = event.currentTarget;
      if (button.disabled) return;

      button.disabled = true;
      var originalHTML = button.dataset.loadingOriginalHtml;
      if (!originalHTML) {
        button.dataset.loadingOriginalHtml = button.innerHTML;
      }
      var spinnerHTML = '<span class="loading-spinner"></span>';
      var buttonText = button.textContent.trim();
      button.innerHTML = spinnerHTML + ' ' + buttonText;
    }

    showSkeletons() {
      this.skeletonTargets.forEach(function(el) { el.style.display = ''; });
      this.contentTargets.forEach(function(el) { el.style.display = 'none'; });
    }

    hideSkeletons() {
      this.skeletonTargets.forEach(function(el) { el.style.display = 'none'; });
      this.contentTargets.forEach(function(el) { el.style.display = ''; });
      this.enableSubmitButtons();
      if (this._safetyTimeout) clearTimeout(this._safetyTimeout);
    }

    disableSubmitButtons() {
      this.submitButtonTargets.forEach(function(btn) {
        btn.disabled = true;
        if (!btn.dataset.loadingOriginalHtml) {
          btn.dataset.loadingOriginalHtml = btn.innerHTML;
        }
        var spinnerHTML = '<span class="loading-spinner"></span>';
        btn.innerHTML = spinnerHTML + ' Loading...';
      });
    }

    enableSubmitButtons() {
      this.submitButtonTargets.forEach(function(btn) {
        btn.disabled = false;
        if (btn.dataset.loadingOriginalHtml) {
          btn.innerHTML = btn.dataset.loadingOriginalHtml;
          delete btn.dataset.loadingOriginalHtml;
        }
      });
    }

    startSafetyTimeout() {
      var self = this;
      this._safetyTimeout = setTimeout(function() {
        self.hideSkeletons();
      }, 10000);
    }
  });
})();
</script>
```

**Step 2: Run tests to verify no regressions**

Run: `bundle exec rspec spec/system/ --fail-fast`
Expected: PASS

**Step 3: Commit**

```bash
git add app/views/layouts/rails_error_dashboard.html.erb
git commit -m "feat: add Stimulus CDN and LoadingController (#43)"
```

---

### Task 3: Add Skeleton Screens for Dashboard Stats

**Files:**
- Modify: `app/views/rails_error_dashboard/errors/index.html.erb` (lines 8-24, wrap stats section with controller and add skeleton)

**Step 1: Write the failing test**

Create: `spec/system/loading_states_spec.rb`

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Loading States", type: :system do
  let!(:application) { create(:application) }
  let!(:error_log) { create(:error_log, application: application) }

  describe "skeleton screens" do
    it "has skeleton placeholders for dashboard stats" do
      visit rails_error_dashboard.errors_path
      wait_for_page_load

      # Skeleton containers exist but are hidden
      expect(page).to have_css(".loading-skeleton", visible: :hidden)
      expect(page).to have_css(".skeleton.skeleton-card", visible: :hidden)
    end

    it "has skeleton placeholders for error list" do
      visit rails_error_dashboard.errors_path
      wait_for_page_load

      expect(page).to have_css(".skeleton.skeleton-row", visible: :hidden)
    end

    it "has a loading controller on the page" do
      visit rails_error_dashboard.errors_path
      wait_for_page_load

      expect(page).to have_css("[data-controller='loading']")
    end
  end

  describe "button loading states" do
    it "has loading action on filter submit button" do
      visit rails_error_dashboard.errors_path
      wait_for_page_load

      expect(page).to have_css("[data-loading-target='submitButton']")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/system/loading_states_spec.rb --fail-fast`
Expected: FAIL (no skeleton elements yet)

**Step 3: Add skeleton stats and loading controller wrapper to index.html.erb**

Wrap the `<div class="py-4">` (line 8) with the loading controller. Add skeleton stats after the real stats:

Replace line 8 (`<div class="py-4">`) with:
```erb
<div class="py-4" data-controller="loading">
```

Replace lines 21-24 (the stats section) with:
```erb
  <!-- Stats Cards -->
  <div id="dashboard_stats" class="mb-4">
    <div data-loading-target="content">
      <%= render "stats", stats: @stats %>
    </div>
    <div class="loading-skeleton" data-loading-target="skeleton">
      <div class="row g-4">
        <% 4.times do %>
          <div class="col-md-3">
            <div class="card stat-card">
              <div class="card-body">
                <div class="skeleton skeleton-text skeleton-text-short mb-2"></div>
                <div class="skeleton skeleton-card"></div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
  </div>
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/system/loading_states_spec.rb --fail-fast`
Expected: PASS

**Step 5: Commit**

```bash
git add app/views/rails_error_dashboard/errors/index.html.erb spec/system/loading_states_spec.rb
git commit -m "feat: add skeleton screens for dashboard stats (#43)"
```

---

### Task 4: Add Skeleton Screens for Error List

**Files:**
- Modify: `app/views/rails_error_dashboard/errors/index.html.erb` (error list table section, lines 362-418)

**Step 1: Add skeleton rows to the error table**

Inside the card-body that contains the table (line 361-418), wrap the table-responsive div and add a skeleton alternative. Replace lines 361-418:

```erb
    <div class="card-body p-0">
      <% if @errors.any? %>
        <div data-loading-target="content">
          <div class="table-responsive">
            <table class="table table-hover mb-0">
              <thead class="table-light">
                <tr>
                  <th style="width: 40px;">
                    <input type="checkbox" id="select-all" class="form-check-input">
                  </th>
                  <th><%= sortable_header("Severity", "severity") %></th>
                  <th><%= sortable_header("Error Type", "error_type") %></th>
                  <th>Message</th>
                  <th><%= sortable_header("Occurrences", "occurrence_count") %></th>
                  <th><%= sortable_header("First / Last Seen", "last_seen_at") %></th>

                  <!-- Show App column only when viewing all apps -->
                  <% if @applications.size > 1 && params[:application_id].blank? %>
                    <th><%= sortable_header("Application", "application_id") %></th>
                  <% end %>

                  <% if @platforms.size > 1 %>
                    <th><%= sortable_header("Platform", "platform") %></th>
                  <% end %>
                  <th>Status</th>
                  <th></th>
                </tr>
              </thead>
              <tbody id="error_list">
                <% @errors.each do |error| %>
                  <%= render "error_row", error: error, show_platform: @platforms.size > 1, show_application: (@applications.size > 1 && params[:application_id].blank?) %>
                <% end %>
              </tbody>
            </table>
          </div>

          <!-- Pagination -->
          <div class="p-3">
            <%== @pagy.series_nav(:bootstrap) if @pagy.pages > 1 %>
          </div>
        </div>

        <div class="loading-skeleton" data-loading-target="skeleton">
          <div class="p-3">
            <% 5.times do %>
              <div class="skeleton skeleton-row mb-2"></div>
            <% end %>
          </div>
        </div>
      <% else %>
        <div class="text-center py-5">
          <i class="bi bi-check-circle display-1 text-success mb-3"></i>
          <h4 class="text-muted">All Clear!</h4>
          <p class="text-muted">
            <% if params[:search].present? || params[:error_type].present? || params[:platform].present? || params[:severity].present? %>
              No errors match your current filters. Try adjusting your search criteria.
            <% else %>
              No errors have been logged yet. Your application is running smoothly!
            <% end %>
          </p>
          <% unless params.values.compact.any? %>
            <small class="text-muted d-block mt-3">
              <i class="bi bi-lightbulb"></i> Errors will appear here automatically when they occur.
            </small>
          <% end %>
        </div>
      <% end %>
    </div>
```

**Step 2: Run tests**

Run: `bundle exec rspec spec/system/loading_states_spec.rb --fail-fast`
Expected: PASS

**Step 3: Commit**

```bash
git add app/views/rails_error_dashboard/errors/index.html.erb
git commit -m "feat: add skeleton screens for error list table (#43)"
```

---

### Task 5: Add Skeleton Screens for Charts

**Files:**
- Modify: `app/views/rails_error_dashboard/errors/index.html.erb` (7-day trend chart section, lines 78-123)

**Step 1: Add skeleton chart placeholders**

Wrap the chart row (lines 79-122) and add a skeleton alternative. Replace lines 78-123:

```erb
  <% if @stats[:errors_trend_7d]&.any? %>
    <div class="row g-4 mb-4">
      <div class="col-md-8" data-loading-target="content">
        <div class="card">
          <div class="card-header bg-white d-flex justify-content-between align-items-center">
            <h5 class="mb-0"><i class="bi bi-graph-up"></i> 7-Day Error Trend</h5>
            <%= link_to analytics_errors_path, class: "btn btn-sm btn-outline-primary" do %>
              <i class="bi bi-bar-chart"></i> Full Analytics
            <% end %>
          </div>
          <div class="card-body">
            <%= line_chart @stats[:errors_trend_7d],
                color: "#8B5CF6",
                curve: false,
                points: true,
                height: "250px",
                library: {
                  plugins: {
                    legend: { display: false }
                  },
                  scales: {
                    y: {
                      beginAtZero: true,
                      ticks: { precision: 0 }
                    }
                  }
                } %>
          </div>
        </div>
      </div>
      <div class="col-md-4" data-loading-target="content">
        <div class="card">
          <div class="card-header bg-white">
            <h5 class="mb-0"><i class="bi bi-pie-chart"></i> By Severity (7d)</h5>
          </div>
          <div class="card-body">
            <%= pie_chart @stats[:errors_by_severity_7d],
                colors: ["#EF4444", "#F59E0B", "#3B82F6", "#6B7280"],
                height: "250px",
                legend: "bottom",
                donut: true %>
          </div>
        </div>
      </div>
    </div>

    <div class="loading-skeleton" data-loading-target="skeleton">
      <div class="row g-4 mb-4">
        <div class="col-md-8">
          <div class="card">
            <div class="card-header bg-white">
              <div class="skeleton skeleton-text" style="width: 200px;"></div>
            </div>
            <div class="card-body">
              <div class="skeleton skeleton-chart"></div>
            </div>
          </div>
        </div>
        <div class="col-md-4">
          <div class="card">
            <div class="card-header bg-white">
              <div class="skeleton skeleton-text" style="width: 150px;"></div>
            </div>
            <div class="card-body">
              <div class="skeleton skeleton-chart"></div>
            </div>
          </div>
        </div>
      </div>
    </div>
  <% end %>
```

**Step 2: Run tests**

Run: `bundle exec rspec spec/system/loading_states_spec.rb --fail-fast`
Expected: PASS

**Step 3: Commit**

```bash
git add app/views/rails_error_dashboard/errors/index.html.erb
git commit -m "feat: add skeleton screens for chart sections (#43)"
```

---

### Task 6: Add Loading State to Filter Form

**Files:**
- Modify: `app/views/rails_error_dashboard/errors/index.html.erb` (filter form, line 194, and submit button, line 321)

**Step 1: Add Stimulus action to filter form**

Replace the form tag (line 194):

```erb
      <%= form_with url: errors_path, method: :get, class: "row g-3", data: { turbo: false, action: "submit->loading#submit" } do %>
```

Replace the submit button section (line 321):

```erb
        <div class="col-12 mt-3">
          <%= submit_tag "Apply Filters", class: "btn btn-primary", data: { loading_target: "submitButton" } %>
          <%= link_to "Clear", errors_path, class: "btn btn-outline-secondary" %>
        </div>
```

**Step 2: Run tests**

Run: `bundle exec rspec spec/system/loading_states_spec.rb --fail-fast`
Expected: PASS

**Step 3: Commit**

```bash
git add app/views/rails_error_dashboard/errors/index.html.erb
git commit -m "feat: add loading state to filter form submit (#43)"
```

---

### Task 7: Add Loading States to Async Action Buttons (show.html.erb)

**Files:**
- Modify: `app/views/rails_error_dashboard/errors/show.html.erb` (modal submit buttons and button_to actions)

**Step 1: Write failing test**

Add to `spec/system/loading_states_spec.rb`:

```ruby
  describe "async action button loading states" do
    let!(:unresolved_error) do
      create(:error_log,
        application: application,
        resolved: false,
        status: "new",
        priority_level: 0)
    end

    it "has loading action on modal submit buttons" do
      visit rails_error_dashboard.error_path(unresolved_error)
      wait_for_page_load

      # The resolve button opens a modal
      expect(page).to have_css("[data-bs-target='#resolveModal']")

      # Modal submit buttons should have loading actions
      expect(page).to have_css("input[data-action='click->loading#click']", visible: :hidden)
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/system/loading_states_spec.rb --fail-fast`
Expected: FAIL

**Step 3: Add loading controller and actions to show.html.erb**

Wrap the main content div with the loading controller. At line 57, replace `<div class="py-4">` with:

```erb
<div class="py-4" data-controller="loading">
```

Update each modal's submit button to include the loading action:

**Resolve Modal** (line 1087): Replace:
```erb
          <%= submit_tag "Mark as Resolved", class: "btn btn-success" %>
```
With:
```erb
          <%= submit_tag "Mark as Resolved", class: "btn btn-success", data: { action: "click->loading#click" } %>
```

**Assign Modal** (line 1114): Replace:
```erb
          <%= submit_tag "Assign", class: "btn btn-primary" %>
```
With:
```erb
          <%= submit_tag "Assign", class: "btn btn-primary", data: { action: "click->loading#click" } %>
```

**Priority Modal** (line 1146): Replace:
```erb
          <%= submit_tag "Update Priority", class: "btn btn-warning" %>
```
With:
```erb
          <%= submit_tag "Update Priority", class: "btn btn-warning", data: { action: "click->loading#click" } %>
```

**Snooze Modal** (line 1188): Replace:
```erb
          <%= submit_tag "Snooze", class: "btn btn-warning" %>
```
With:
```erb
          <%= submit_tag "Snooze", class: "btn btn-warning", data: { action: "click->loading#click" } %>
```

**Step 4: Run tests**

Run: `bundle exec rspec spec/system/loading_states_spec.rb --fail-fast`
Expected: PASS

**Step 5: Run full system test suite**

Run: `bundle exec rspec spec/system/ --fail-fast`
Expected: PASS (no regressions in existing workflow tests)

**Step 6: Commit**

```bash
git add app/views/rails_error_dashboard/errors/show.html.erb spec/system/loading_states_spec.rb
git commit -m "feat: add loading states to async action buttons (#43)"
```

---

### Task 8: Final Verification and Full Test Suite

**Step 1: Run full RSpec suite**

Run: `bundle exec rspec --fail-fast`
Expected: PASS (all ~1656 specs)

**Step 2: Run RuboCop**

Run: `bundle exec rubocop`
Expected: PASS (no new offenses)

**Step 3: Manual visual verification (optional)**

Run: `HEADLESS=false bundle exec rspec spec/system/loading_states_spec.rb`
Expected: Visually verify skeletons and loading states appear correctly

**Step 4: Final commit if any fixes needed**

If any test failures were fixed, commit those fixes.
