---
layout: default
title: "Mobile App Error Reporting Integration"
order: 11
---

# Mobile App Error Reporting Integration

RED has no mobile SDK and no endpoint that accepts errors. To see a mobile app's errors in the
dashboard, add a small endpoint to your own Rails app that receives them and passes each one to
`RailsErrorDashboard::ManualErrorReporter.report`. They are then stored with your server's errors,
shown in the same dashboard, and sent to the same notification channels.

This guide uses a React Native app as the client, but the endpoint works for any client that can
post JSON.

---

## The endpoint

```ruby
# app/controllers/api/v1/mobile_errors_controller.rb
module Api
  module V1
    class MobileErrorsController < ActionController::API
      before_action :authenticate_app!
      rate_limit to: 30, within: 1.minute # Rails 7.2+

      MAX_BATCH = 50
      PLATFORMS = { "ios" => "iOS", "android" => "Android" }.freeze

      # POST /api/v1/mobile_errors
      def create
        report(error_params(params.require(:error)))
        head :created
      end

      # POST /api/v1/mobile_errors/batch
      def batch
        errors = Array(params.require(:errors)).first(MAX_BATCH)
        errors.each { |error| report(error_params(error)) }
        render json: { accepted: errors.size }, status: :created
      end

      private

      # Replace with your API's own check. As written, it lets in signed-in users only.
      def authenticate_app!
        head :unauthorized unless current_user
      end

      def error_params(error)
        error.permit(:error_type, :message, :stack, :component, :timestamp, :platform, :app_version,
                     context: {})
      end

      def report(error)
        RailsErrorDashboard::ManualErrorReporter.report(
          error_type: error[:error_type].presence || "MobileError",
          message: error[:message].presence || "Mobile app error",
          backtrace: error[:stack],
          platform: PLATFORMS.fetch(error[:platform].to_s.downcase, error[:platform]),
          app_version: error[:app_version],
          user_id: current_user&.id,
          occurred_at: error[:timestamp].present? ? Time.at(error[:timestamp].to_i / 1000.0) : nil,
          user_agent: request.user_agent,
          ip_address: request.remote_ip,
          metadata: { component: error[:component], context: error[:context]&.to_h }.compact_blank,
          source: "mobile_app"
        )
      end
    end
  end
end
```

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :mobile_errors, only: [ :create ] do
      post :batch, on: :collection
    end
  end
end
```

What each part is for:

- **`platform`:** React Native's `Platform.OS` gives `"ios"` and `"android"`. The dashboard's iOS and
  Android badges, and its mobile counts, match only `"iOS"` and `"Android"`, so the endpoint maps
  them. RED doesn't work the platform out from the User-Agent here: without `platform:`, the error
  is stored as `"API"`.
- **`occurred_at`:** the app sends milliseconds since the epoch. `ManualErrorReporter` takes a
  `Time` or a date string; it ignores a bare number and uses the current time. An error the app
  saved while offline keeps its real time on its occurrence; see
  [`ManualErrorReporter.report`](/rails_error_dashboard/docs/reference/api-reference/#manualerrorreporterreport).
- **`metadata`:** it must be a plain Hash; RED drops anything else. Permitted params aren't one,
  hence the `.to_h` on `context`. RED shows it with the request params on the error's page.
- **`current_user`:** whatever your API uses to know the signed-in user. Leave `user_id` out if the
  app has no users.
- **The batch action** caps the number of errors per request, and answers only after reporting them,
  so the app can treat a `201` as delivered. `accepted` counts the errors handed to RED, including
  any it then ignores, samples out or only counts during a storm.
- **Protect it.** The endpoint is part of your API, not of the dashboard: RED's
  [rate limiting](/rails_error_dashboard/docs/reference/api-reference/#rate-limiting) covers only the dashboard. As written,
  `authenticate_app!` refuses anyone who isn't signed in; replace it with your API's own check, such
  as an app token, if you want errors from before sign-in. The client chooses `error_type`, and
  severity comes from it, so an open endpoint lets anyone send critical alerts. Limit it too:
  `rate_limit` needs Rails 7.2 or later; on older Rails, use Rack::Attack. An
  `ActionController::API` controller has no CSRF check; if yours inherits from
  `ActionController::Base`, add `skip_forgery_protection`.

`ManualErrorReporter.report` returns the saved error, or `nil` when `config.async_logging` is on
(a background job saves it), or when RED ignores the error, samples it out, or only counts it during
a storm. The endpoint doesn't depend on the return value.

---

## The React Native client

These are the parts that talk to the endpoint. Storing errors while offline and deciding when to
sync are up to your app.

### Sending errors

```typescript
// src/services/errorReporter.ts
import { Platform } from 'react-native';
import { api } from './api'; // your HTTP client, with the base URL and auth

export type ReportedError = {
  error_type: string;
  message: string;
  stack?: string;
  component?: string;
  timestamp: number; // Date.now()
  platform: string;  // Platform.OS
  app_version: string;
  context?: Record<string, unknown>;
};

export function toReport(error: Error, component?: string, context?: Record<string, unknown>): ReportedError {
  return {
    error_type: error.name,
    message: error.message,
    stack: error.stack,
    component,
    timestamp: Date.now(),
    platform: Platform.OS,
    app_version: '2.1.0', // e.g. from expo-application or react-native-device-info
    context,
  };
}

export async function reportError(report: ReportedError): Promise<void> {
  await api.post('/api/v1/mobile_errors', { error: report });
}

// Send stored errors; drop them from storage only after a 201.
export async function reportBatch(reports: ReportedError[]): Promise<boolean> {
  const response = await api.post('/api/v1/mobile_errors/batch', { errors: reports.slice(0, 50) });
  return response.status === 201;
}
```

### Catching render errors

```typescript
// src/components/ErrorBoundary.tsx
import React from 'react';
import { reportError, toReport } from '../services/errorReporter';

export class ErrorBoundary extends React.Component<{ children: React.ReactNode }> {
  componentDidCatch(error: Error, info: React.ErrorInfo) {
    reportError(toReport(error, 'ErrorBoundary', { componentStack: info.componentStack }));
  }

  render() {
    return this.props.children;
  }
}
```

---

## Try it

Add the header your API signs requests in with; without it, `authenticate_app!` answers `401`.

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://localhost:3000/api/v1/mobile_errors \
  -H 'Content-Type: application/json' \
  -d '{"error":{"error_type":"TypeError","message":"Cannot read properties of undefined (reading '"'"'id'"'"')","stack":"at renderCart (cart.js:42)\nat onPress (button.js:15)","component":"CartScreen","timestamp":1767225600000,"platform":"ios","app_version":"2.1.0","context":{"cartId":7}}}'
# => 201
```

Then open the dashboard. The error is in the list, with the iOS badge when your errors come from
more than one platform. Filter by platform with `/red/errors?platform=iOS`.

---

## What the dashboard shows

- **Platform:** iOS and Android badges in the error list, which shows a Platform column once errors
  come from more than one platform. Filter with `?platform=iOS`.
- **App version:** the `app_version` you sent, also used by the Releases page.
- **Component and context:** with the request params on the error's page.
- **Backtrace:** the stack you sent, cut to `config.max_backtrace_lines` (100 by default).
- **User:** the `user_id` you sent.
- **Analytics:** the Analytics page's "Errors by Platform" chart, shown once errors come from more
  than one platform, and resolution time by platform.

---

## Notifications

Mobile errors go to the channels you set up, under the same rules as server errors. A Slack message
has the application, error type, platform, environment, time and message, then the user (when the
error has one), IP address and request URL (`mobile_app`, from `source:`, since there is no request URL), a **View Details**
button and the error's ID. An email has the platform, the first 10 backtrace lines and a link to the
dashboard. See [Notifications](/rails_error_dashboard/docs/guides/notifications/).

---

## Troubleshooting

### Errors don't appear in the dashboard

1. Check the endpoint answers `201`, with the `curl` above. A `401` means `authenticate_app!` didn't
   find a signed-in user. A `400` means the JSON has no `error` (or `errors`) key. A `429` means the
   endpoint's rate limit.
2. With `config.async_logging` on, a background job saves each error, so a worker must be running.
   See [Run a worker for RED's jobs](/rails_error_dashboard/docs/production/#1-run-a-worker-for-reds-jobs).
3. Check RED isn't dropping the error on purpose: `ignored_exceptions`, `sampling_rate`, or storm
   protection during a flood.

### Errors show the platform as API

The app didn't send `platform`, or sent a value the endpoint doesn't map. Send `Platform.OS`.

### The time is wrong

The app sent `timestamp` in seconds, or as a date string, instead of milliseconds since the epoch.

### Too many errors

The endpoint's rate limit and batch cap bound what one client can send. RED's storm protection also
counts floods of errors without saving each one. On the client, don't report the same error over
and over in a loop.

---

## Security

- The endpoint is yours: authenticate the app and rate-limit it.
- Error messages and context end up in the dashboard and in notifications. Don't send tokens,
  passwords or personal data.
- Treat what the app sends as untrusted input: the endpoint permits only known fields and caps the
  batch.
