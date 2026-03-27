---
layout: default
title: "Mobile App Error Reporting Integration"
permalink: /docs/guides/MOBILE_APP_INTEGRATION
---

# Mobile App Error Reporting Integration

This guide explains how to integrate the Rails Error Dashboard with your React Native/Expo mobile application.

## Overview

The gem provides a centralized error tracking system that works seamlessly with mobile apps. Mobile errors are:
- Reported to the API via dedicated endpoints
- Stored in the same database as server errors
- Displayed in the same dashboard with platform detection (iOS/Android)
- Trigger the same notification system (Slack + Email)

## Benefits

✅ **Centralized error tracking** - All errors (API + iOS + Android) in one place
✅ **Platform detection** - Automatically tagged as iOS or Android
✅ **Real-time notifications** - Team gets alerted via Slack/Email
✅ **Offline support** - Errors stored locally and synced when online
✅ **Batch processing** - Multiple errors sent efficiently
✅ **User context** - Errors associated with logged-in user

## Backend Setup (Rails API)

### 1. Create Mobile Errors Controller

```ruby
# app/controllers/api/v1/mobile_errors_controller.rb
module Api
  module V1
    class MobileErrorsController < BaseController
      # POST /api/v1/mobile_errors
      def create
        mobile_error = MobileError.new(error_params)

        RailsErrorDashboard::Commands::LogError.call(
          mobile_error,
          {
            current_user: current_user,
            request: request,
            source: :mobile_app,
            additional_context: {
              component: error_params[:component],
              device_info: error_params[:device_info]
            }
          }
        )

        render json: { success: true }, status: :created
      end

      # POST /api/v1/mobile_errors/batch
      def batch
        # Handle batch error reporting
        # See full implementation in the gem's example
      end

      private

      def error_params
        params.require(:error).permit(
          :error_type, :message, :stack, :component, :timestamp,
          device_info: [:platform, :version]
        )
      end

      class MobileError < StandardError
        attr_reader :mobile_data

        def initialize(data)
          @mobile_data = data
          super(data[:message] || 'Mobile app error')
        end

        def name
          @mobile_data[:error_type] || 'MobileError'
        end

        def backtrace
          @mobile_data[:stack]&.split("\n") || []
        end
      end
    end
  end
end
```

### 2. Add Routes

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :mobile_errors, only: [:create] do
      collection do
        post 'batch'
      end
    end
  end
end
```

## Mobile App Setup (React Native/Expo)

### 1. Add Error Reporting Methods to API Client

```typescript
// src/services/api.ts
class APIClient {
  // ... existing code ...

  async reportError(errorData: {
    error_type: string;
    message: string;
    stack?: string;
    component?: string;
    timestamp: number;
    device_info: {
      platform: string;
      version: string;
    };
  }): Promise<{ success: boolean; message: string }> {
    const response = await this.client.post('/mobile_errors', {
      error: errorData
    });
    return response.data;
  }

  async reportErrorsBatch(errors: Array<{...}>): Promise<{...}> {
    const response = await this.client.post('/mobile_errors/batch', { errors });
    return response.data;
  }
}
```

### 2. Update Error Logger Service

```typescript
// src/services/errorLogger.ts
import { api } from './api';

class ErrorLogger {
  async syncErrors(): Promise<void> {
    const unsyncedErrors = (await this.getLocalErrors()).filter(e => !e.synced);

    if (unsyncedErrors.length === 0) return;

    const batches = this.chunkArray(unsyncedErrors, 10);

    for (const batch of batches) {
      try {
        // Send to backend
        const result = await api.reportErrorsBatch(batch.map(error => ({
          error_type: error.error_type,
          message: error.message,
          stack: error.stack,
          component: error.component,
          timestamp: error.timestamp,
          device_info: error.device_info,
        })));

        // Mark as synced
        await this.markErrorsAsSynced(batch);
      } catch (e) {
        console.error('Failed to sync batch:', e);
      }
    }
  }
}
```

### 3. Use Error Logger Throughout App

```typescript
// In components
import { errorLogger } from '../services/errorLogger';

try {
  // Your code
} catch (error) {
  await errorLogger.logError(
    error as Error,
    'RecordingScreen',
    { action: 'startRecording' }
  );
}
```

### 4. Add Global Error Boundary

```typescript
// src/components/common/ErrorBoundary.tsx
import React from 'react';
import { errorLogger } from '../../services/errorLogger';

class ErrorBoundary extends React.Component {
  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    errorLogger.logError(error, 'ErrorBoundary', {
      componentStack: errorInfo.componentStack,
    });
  }

  render() {
    return this.props.children;
  }
}
```

## Error Flow

```text
┌─────────────────┐
│   Mobile App    │
│   Error Occurs  │
└────────┬────────┘
         │
         ▼
┌─────────────────────┐
│  ErrorLogger        │
│  - Store locally    │
│  - Sync to API      │
└────────┬────────────┘
         │
         ▼
┌─────────────────────────────────┐
│  Rails API                      │
│  POST /api/v1/mobile_errors     │
└────────┬────────────────────────┘
         │
         ▼
┌───────────────────────────────────┐
│  Rails Error Dashboard Gem       │
│  RailsErrorDashboard::           │
│    Commands::LogError.call       │
└────────┬──────────────────────────┘
         │
         ├────────────────┬──────────────────┐
         ▼                ▼                  ▼
┌─────────────┐  ┌──────────────┐  ┌────────────────┐
│  Database   │  │ Slack Alert  │  │  Email Alert   │
│  Storage    │  │  (async job) │  │  (async job)   │
└─────────────┘  └──────────────┘  └────────────────┘
         │
         ▼
┌─────────────────────────┐
│  Error Dashboard        │
│  /error_dashboard       │
│  - View by platform     │
│  - iOS/Android filters  │
│  - Analytics            │
└─────────────────────────┘
```

## Features in Dashboard

Once integrated, you'll see:

- **Platform Badges**: iOS 📱 or Android 🤖 tags on errors
- **Device Info**: OS version, app version
- **Component Context**: Which screen/component errored
- **Stack Traces**: Full JavaScript stack traces
- **User Context**: Which user experienced the error
- **Filtering**: Filter dashboard by platform (iOS/Android/API)
- **Analytics**: Charts showing errors by platform

## Notifications

When a mobile error occurs:

### Slack Notification:
```text
🚨 Error Alert
━━━━━━━━━━━━━━━━━━━━━
Error Type: TypeError
Environment: Production
Platform: 📱 iOS
Occurred: December 24, 2025 at 10:30 AM

Message:
Cannot read property 'id' of undefined

User: user@example.com
Component: RecordingScreen

[View Details] → Dashboard link
```

### Email Notification:
- Beautiful HTML email with error details
- Platform badge (iOS/Android)
- Stack trace (first 10 lines)
- Link to dashboard
- Sent to configured recipients

## Testing

### 1. Test Error Logging
```typescript
// In your app
errorLogger.logError(
  new Error('Test mobile error'),
  'TestScreen',
  { test: true }
);
```

### 2. Check Local Storage
```typescript
const stats = await errorLogger.getStats();
console.log('Errors:', stats.total, 'Synced:', stats.synced);
```

### 3. Verify in Dashboard
1. Open `http://localhost:3000/red`
2. Filter by platform: iOS or Android
3. Check error details
4. Verify user association
5. Check notifications (Slack/Email)

## Best Practices

### 1. Error Context
Always provide component name and relevant context:
```typescript
await errorLogger.logError(error, 'RecordingScreen', {
  action: 'startRecording',
  recordingId: recording.id,
  duration: 120,
});
```

### 2. Sync Strategy
- Sync immediately for critical errors
- Batch sync for non-critical errors
- Periodic sync every 15 minutes (default)
- Sync on app foreground

### 3. Storage Management
- Keep max 50 errors locally
- Clean up synced errors > 20
- Implement exponential backoff for failed syncs

### 4. Privacy
- Don't log sensitive user data
- Sanitize error messages
- Avoid logging tokens/passwords

## Configuration

### Backend
```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.enable_slack_notifications = true
  config.enable_email_notifications = true
  config.notification_email_recipients = ['dev@example.com']
  config.dashboard_base_url = 'https://myapp.com'
end
```

### Mobile App
```typescript
// Start periodic sync when app loads
errorLogger.startPeriodicSync(15); // Every 15 minutes

// Stop sync when app closes
errorLogger.stopPeriodicSync();
```

## Troubleshooting

### Errors not appearing in dashboard?
1. Check API endpoint is accessible
2. Verify authentication token is valid
3. Check Rails logs for controller errors
4. Verify error format matches expected params

### Notifications not sending?
1. Check notification settings in initializer
2. Verify Slack webhook URL is valid
3. Check email recipients are configured
4. Check background job queue is running

### High error volume?
1. Implement client-side error deduplication
2. Add rate limiting to error reporting
3. Filter out known/handled errors
4. Set up error grouping by type

## Security

- ✅ Error endpoints require authentication
- ✅ Rate limiting on error reporting endpoints
- ✅ Input validation and sanitization
- ✅ No PII in error messages
- ✅ Secure token storage on mobile

## Performance

- ✅ Async error reporting (non-blocking)
- ✅ Batch processing (max 10 errors per request)
- ✅ Local storage with cleanup
- ✅ Background job processing
- ✅ Minimal app overhead

---

**Made with ❤️  by Anjan for the Rails community**
