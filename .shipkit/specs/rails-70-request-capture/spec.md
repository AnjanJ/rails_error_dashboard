# Spec: Rails 7.0 request capture

> Spec accepted at commit `bd08d75` on spec/0-16-1.
> Status: open
> Paths: lib/rails_error_dashboard.rb,lib/rails_error_dashboard/engine.rb,lib/rails_error_dashboard/middleware/,spec/

## Purpose
A Rails 7.0 app records no unhandled request errors: Rails renders the error page without
reporting the exception, and RED's middleware sits outside the code that renders it. 0.16.0
shipped this as a known limitation. Record these errors on 7.0 the way 7.1+ already does, and
never record one twice. See `intake.md`.

## User stories
- As a developer on Rails 7.0, I want an exception that breaks a request recorded in RED, so the
  dashboard shows the errors my users actually hit.

## Requirements (EARS)

### What Rails 7.0 records
- **REQ-1.** While the host app runs Rails 7.0 with production settings (`show_exceptions` on,
  detailed exceptions off), when a request raises an exception its controller does not rescue,
  RED shall record that exception exactly once.
- **REQ-2.** While the host app runs Rails 7.0 with development settings (detailed exceptions on),
  when a request raises an exception its controller does not rescue, RED shall record that
  exception exactly once.
- **REQ-3.** While the host app runs Rails 7.0 with `show_exceptions` off, when a request raises an
  exception its controller does not rescue, RED shall record that exception exactly once.

### What Rails 7.0 does not record
- **REQ-4.** While the host app runs Rails 7.0 with `show_exceptions` on, if the exception is one
  Rails answers with a rescue response (a class in
  `ActionDispatch::ExceptionWrapper.rescue_responses`, such as `ActionController::RoutingError`
  or `ActiveRecord::RecordNotFound`), then RED shall not record it, as Rails 7.1 does not.
- **REQ-5.** When a controller's `rescue_from` handles an exception on Rails 7.0, RED shall not
  record it.

### What the record and the response look like
- **REQ-6.** When RED records a request exception on Rails 7.0, the error shall carry the
  request's URL, HTTP method, controller and action, and shall be a server capture.
- **REQ-7.** When RED records a request exception on Rails 7.0, the host app shall send the
  response it sends without RED installed (the same status and body).
- **REQ-8.** If recording a request exception fails inside RED on Rails 7.0, then the host app
  shall still send the error response Rails renders.

### Rails 7.1 and later
- **REQ-9.** While the host app runs Rails 7.1 or later, RED shall record an unhandled request
  exception exactly once, as 0.16.0 does.

## Out of scope
- Moving RED's middleware on Rails 7.1+, or changing what 7.1+ records.
- Running the chaos suite's Phase F on Rails 7.0.
- Dropping Rails 7.0 support.

## Release steps
Not requirements, because they describe the release rather than the product:
- Verify in a real Rails 7.0.8.7 app in production mode, and record the run with the release
  scenarios.
- The 0.16.1 release notes say the 0.16.0 "Known limitation: Rails 7.0" is fixed. The 0.16.0
  CHANGELOG section stays as written.
