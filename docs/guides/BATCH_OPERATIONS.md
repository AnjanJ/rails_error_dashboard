# Batch Operations Guide

Rails Error Dashboard supports batch operations to efficiently manage multiple errors at once.

## Features

- **Batch Resolve**: Mark multiple errors as resolved simultaneously
- **Batch Delete**: Delete multiple errors in one operation
- **Select All**: Quickly select all errors on the current page
- **Visual Feedback**: Real-time selection count and toolbar
- **Safe Operations**: Confirmation dialogs for destructive actions

---

## Using Batch Operations

### 1. Accessing Batch Operations

Batch operations are available on the main error listing page (`/error_dashboard/errors`).

### 2. Selecting Errors

**Select Individual Errors:**
- Click the checkbox in the leftmost column of any error row
- The batch actions toolbar will appear automatically

**Select All Errors on Page:**
- Click the checkbox in the table header
- All errors on the current page will be selected

**Clear Selection:**
- Click the "Clear Selection" button in the toolbar
- Or uncheck individual errors

### 3. Batch Actions

Once you've selected one or more errors, the batch actions toolbar appears with:

#### Resolve Selected
- **Button**: Green "Resolve Selected" button
- **Action**: Marks all selected errors as resolved
- **Fields**: Currently resolves without comment (instant resolution)
- **Use Case**: Quickly resolve multiple errors after deploying a fix

#### Delete Selected
- **Button**: Red "Delete Selected" button
- **Action**: Permanently deletes selected errors from the database
- **Confirmation**: Shows confirmation dialog before deletion
- **Use Case**: Clean up test errors or false positives

---

## UI Workflow

```text
1. User visits /error_dashboard/errors
   ↓
2. User clicks checkboxes to select errors
   ↓
3. Batch toolbar appears showing "N selected"
   ↓
4. User clicks "Resolve Selected" or "Delete Selected"
   ↓
5. Confirmation dialog (for delete only)
   ↓
6. Batch operation executes
   ↓
7. Success/failure flash message appears
   ↓
8. Page redirects to error list
```

---

## Backend Architecture

### Commands

Batch operations use dedicated Command objects following the CQRS pattern:

#### BatchResolveErrors Command

**File**: `lib/rails_error_dashboard/commands/batch_resolve_errors.rb`

**Usage:**
```ruby
# Resolve multiple errors
result = RailsErrorDashboard::Commands::BatchResolveErrors.call(
  [123, 456, 789],
  resolved_by_name: "John Doe",
  resolution_comment: "Fixed in PR #123"
)

# Returns:
{
  success: true,
  count: 3,           # Number successfully resolved
  total: 3,           # Total attempted
  failed_ids: [],     # IDs that failed (if any)
  errors: []          # Error messages (if any)
}
```

**Features:**
- Accepts array of error IDs
- Optional resolver name and comment
- Handles partial failures gracefully
- Returns detailed result hash

#### BatchDeleteErrors Command

**File**: `lib/rails_error_dashboard/commands/batch_delete_errors.rb`

**Usage:**
```ruby
# Delete multiple errors
result = RailsErrorDashboard::Commands::BatchDeleteErrors.call([123, 456, 789])

# Returns:
{
  success: true,
  count: 3,           # Number successfully deleted
  total: 3,           # Total attempted
  errors: []          # Error messages (if any)
}
```

**Features:**
- Accepts array of error IDs
- Uses `destroy_all` for efficiency
- Returns detailed result hash

### Controller Action

**File**: `app/controllers/rails_error_dashboard/errors_controller.rb`

**Route**: `POST /error_dashboard/errors/batch_action`

**Parameters:**
- `error_ids[]` - Array of error IDs to process
- `action_type` - Either "resolve" or "delete"
- `resolved_by_name` - (Optional) Name of person resolving
- `resolution_comment` - (Optional) Comment about resolution

**Response:**
- Success: Redirects with flash notice
- Failure: Redirects with flash alert

---

## JavaScript Implementation

The batch operations UI is powered by vanilla JavaScript (no dependencies).

**File**: `app/views/rails_error_dashboard/errors/index.html.erb` (inline script)

### Key Features

1. **Select All Checkbox**
   - Clicking selects/deselects all errors on page
   - Shows indeterminate state when some (but not all) selected

2. **Individual Checkboxes**
   - Each error has its own checkbox
   - Updates "select all" state automatically
   - Shows/hides batch toolbar based on selection

3. **Batch Toolbar**
   - Hidden by default
   - Appears when 1+ errors selected
   - Shows count of selected errors
   - Contains action buttons

4. **Form Submission**
   - Dynamically adds hidden inputs for selected error IDs
   - Prevents submission if no errors selected
   - Confirmation dialog for destructive actions

---

## Examples

### Example 1: Resolve Multiple Test Errors

```ruby
# After deploying a fix for NoMethodError in UsersController
# Go to error dashboard, filter by error type
# Select all NoMethodError instances
# Click "Resolve Selected"
# ✅ All instances marked as resolved

# Or via console:
error_ids = RailsErrorDashboard::ErrorLog
  .where(error_type: "NoMethodError")
  .where(controller_name: "UsersController")
  .pluck(:id)

RailsErrorDashboard::Commands::BatchResolveErrors.call(
  error_ids,
  resolved_by_name: "Deploy Bot",
  resolution_comment: "Fixed in release v2.3.1"
)
```

### Example 2: Delete Old Development Errors

```ruby
# Clean up errors from development environment
dev_error_ids = RailsErrorDashboard::ErrorLog
  .where(environment: "development")
  .where("occurred_at < ?", 1.week.ago)
  .pluck(:id)

RailsErrorDashboard::Commands::BatchDeleteErrors.call(dev_error_ids)
# Returns: { success: true, count: 45, total: 45, errors: [] }
```

### Example 3: Partial Failure Handling

```ruby
# Some errors might be locked or invalid
result = RailsErrorDashboard::Commands::BatchResolveErrors.call([1, 2, 999999])

if result[:success]
  puts "All #{result[:count]} errors resolved"
else
  puts "Resolved #{result[:count]} of #{result[:total]}"
  puts "Failed IDs: #{result[:failed_ids].join(', ')}"
  puts "Errors: #{result[:errors].join(', ')}"
end
```

---

## UI Screenshots (Workflow)

### Step 1: Error List (No Selection)
```text
┌─────────────────────────────────────────────────────────┐
│  Recent Errors                            25 items      │
├─────┬──────┬────────────┬─────────┬─────────┬──────────┤
│  ☐  │ Time │ Error Type │ Message │ Platform│ Status   │
├─────┼──────┼────────────┼─────────┼─────────┼──────────┤
│  ☐  │ 10am │ NoMethod..  │ Error..  │ iOS     │ ⚠️       │
│  ☐  │ 9am  │ Argument..  │ Error..  │ Android │ ⚠️       │
│  ☐  │ 8am  │ Runtime..   │ Error..  │ API     │ ⚠️       │
└─────┴──────┴────────────┴─────────┴─────────┴──────────┘
```

### Step 2: Errors Selected (Toolbar Appears)
```text
┌─────────────────────────────────────────────────────────┐
│  Recent Errors                            25 items      │
├─────────────────────────────────────────────────────────┤
│ 3 selected  [✓ Resolve Selected] [✗ Delete Selected]   │
│                                    [Clear Selection]    │
├─────┬──────┬────────────┬─────────┬─────────┬──────────┤
│  ☑  │ Time │ Error Type │ Message │ Platform│ Status   │
├─────┼──────┼────────────┼─────────┼─────────┼──────────┤
│  ☑  │ 10am │ NoMethod..  │ Error..  │ iOS     │ ⚠️       │
│  ☑  │ 9am  │ Argument..  │ Error..  │ Android │ ⚠️       │
│  ☑  │ 8am  │ Runtime..   │ Error..  │ API     │ ⚠️       │
└─────┴──────┴────────────┴─────────┴─────────┴──────────┘
```

---

## API Reference

### BatchResolveErrors.call(error_ids, options)

**Parameters:**
- `error_ids` (Array<Integer>) - Array of error log IDs to resolve
- `options` (Hash) - Optional parameters
  - `resolved_by_name` (String) - Name of person/system resolving
  - `resolution_comment` (String) - Comment about the resolution

**Returns:**
Hash with keys:
- `success` (Boolean) - True if all errors resolved successfully
- `count` (Integer) - Number of errors successfully resolved
- `total` (Integer) - Total number of errors attempted
- `failed_ids` (Array<Integer>) - IDs that failed to resolve
- `errors` (Array<String>) - Error messages for failures

**Example:**
```ruby
result = RailsErrorDashboard::Commands::BatchResolveErrors.call(
  [1, 2, 3],
  resolved_by_name: "Alice",
  resolution_comment: "Fixed in PR #456"
)
# => { success: true, count: 3, total: 3, failed_ids: [], errors: [] }
```

### BatchDeleteErrors.call(error_ids)

**Parameters:**
- `error_ids` (Array<Integer>) - Array of error log IDs to delete

**Returns:**
Hash with keys:
- `success` (Boolean) - True if all errors deleted successfully
- `count` (Integer) - Number of errors successfully deleted
- `total` (Integer) - Total number of errors attempted
- `errors` (Array<String>) - Error messages for failures

**Example:**
```ruby
result = RailsErrorDashboard::Commands::BatchDeleteErrors.call([1, 2, 3])
# => { success: true, count: 3, total: 3, errors: [] }
```

---

## Performance Considerations

### Scalability

**Recommended Limits:**
- **Per-page selection**: Up to 100 errors (default page size is 25)
- **Large batch operations**: Use Rails console for 100+ errors
- **Database impact**: Batch operations use ActiveRecord transactions

### For Large Datasets

If you need to process 100+ errors:

```ruby
# Use batching to avoid memory issues
error_ids = RailsErrorDashboard::ErrorLog
  .where(resolved: false)
  .where("occurred_at < ?", 1.month.ago)
  .pluck(:id)

# Process in batches of 100
error_ids.each_slice(100) do |batch|
  result = RailsErrorDashboard::Commands::BatchResolveErrors.call(
    batch,
    resolved_by_name: "Automated Cleanup",
    resolution_comment: "Auto-resolved old errors"
  )

  puts "Batch: #{result[:count]}/#{result[:total]} resolved"
end
```

---

## Limitations

1. **Page-level Selection**
   - "Select All" only selects errors on current page
   - Does not select across multiple pages
   - For cross-page operations, use Rails console

2. **No Undo**
   - Batch operations are immediate and permanent
   - Resolved errors can be un-resolved manually
   - Deleted errors cannot be recovered

3. **Permissions**
   - Batch operations require dashboard authentication
   - No role-based access control (RBAC) currently

---

## Future Enhancements

Planned features for future versions:

- [ ] **Batch resolve with comments** - Add UI form for resolution details
- [ ] **Select all across pages** - Select all matching filter criteria
- [ ] **Batch unresolve** - Reopen resolved errors in batch
- [ ] **Background job processing** - For very large batch operations
- [ ] **Audit trail** - Track who performed batch operations
- [ ] **Role-based permissions** - Restrict batch delete to admins
- [ ] **Preview mode** - Show which errors will be affected before action

---

## Troubleshooting

### Toolbar Not Appearing

**Problem**: Batch toolbar doesn't show when selecting errors

**Solutions:**
- Ensure JavaScript is enabled
- Check browser console for errors
- Verify Bootstrap CSS is loaded
- Clear browser cache

### Selection State Lost on Pagination

**Problem**: Selections cleared when changing pages

**Expected Behavior**: Selections are per-page only. This is intentional.

**Workaround**: Use filters to narrow down errors first, then select and batch process.

### Batch Operation Failed

**Problem**: Flash message shows "Batch operation failed"

**Debug Steps:**
1. Check Rails logs for error details
2. Verify error IDs are valid
3. Check database constraints
4. Ensure errors aren't locked by another process

---

## Related Documentation

- [Main README](../README.md) - Overall gem documentation
- [Notifications](NOTIFICATIONS.md) - Notification setup

---

**Batch operations are fully functional!** 🎉

See the [Plugin System](../PLUGIN_SYSTEM.md) guide for building custom integrations.
