# Tasks: Webhook contract v1

Test first in every task: the cited test fails before the change and passes after it. Every test
cites `webhook-v1/REQ-N`. One commit per task, test and code together.

`R` below stands for `env -u RAILS_VERSION bin/with-ruby bundle exec`. Run one rspec process at a
time.

- [x] **T1** One list of event names, and the three renames → REQ-5, REQ-6, REQ-7, REQ-8, REQ-12
  - Files: lib/rails_error_dashboard/webhooks.rb, lib/rails_error_dashboard.rb, lib/rails_error_dashboard/services/webhook_payload_builder.rb, lib/rails_error_dashboard/services/baseline_alert_payload_builder.rb, app/jobs/rails_error_dashboard/storm_notification_job.rb, app/jobs/rails_error_dashboard/notification_burst_summary_job.rb, spec/lib/rails_error_dashboard/webhooks_spec.rb, spec/jobs/rails_error_dashboard/storm_notification_job_spec.rb, spec/jobs/rails_error_dashboard/notification_burst_summary_job_spec.rb, spec/jobs/rails_error_dashboard/baseline_alert_job_spec.rb, spec/lib/rails_error_dashboard/services/baseline_alert_payload_builder_spec.rb, spec/lib/rails_error_dashboard/services/webhook_payload_builder_spec.rb
  - Test:
    - webhooks_spec: `Webhooks::EVENTS` holds exactly `error.created`, `storm.detected`,
      `notifications.suppressed` and `baseline.anomaly_detected`, and no `event: "` literal is
      left in the four builders;
    - the job and builder specs post those names;
    - a storm job enqueued with 0.17.0's arguments (`started_at:`, `state:`, `locale:`) posts
      `storm.detected` (REQ-12)
  - After: none
  - Done when: `R rspec spec/lib/rails_error_dashboard/webhooks_spec.rb spec/jobs/rails_error_dashboard spec/lib/rails_error_dashboard/services/baseline_alert_payload_builder_spec.rb spec/lib/rails_error_dashboard/services/webhook_payload_builder_spec.rb` → 0 failures
- [x] **T2** The envelope and headers, applied in `WebhookDelivery` → REQ-1, REQ-2, REQ-3, REQ-4, REQ-9, REQ-10, REQ-11
  - Files: lib/rails_error_dashboard/services/webhook_delivery.rb, lib/rails_error_dashboard/services/webhook_payload_builder.rb, lib/rails_error_dashboard/services/baseline_alert_payload_builder.rb, app/jobs/rails_error_dashboard/storm_notification_job.rb, app/jobs/rails_error_dashboard/notification_burst_summary_job.rb, app/jobs/rails_error_dashboard/webhook_error_notification_job.rb, spec/lib/rails_error_dashboard/services/webhook_delivery_spec.rb, spec/lib/rails_error_dashboard/services/webhook_contract_spec.rb, spec/support/webhook_contract.rb
  - Test:
    - webhook_contract_spec, for each of the four events, through the real job with WebMock:
      - the body has `version: 1`, `event`, and a UTC `timestamp`;
      - `X-Error-Dashboard-Event` equals `event`;
      - `X-Error-Dashboard-ID` is present for `error.created` and `baseline.anomaly_detected`, and
        absent for storm and burst;
      - with a signing secret, `WebhookSigner.valid?` accepts the exact bytes sent;
      - every key a 0.17.0 body had is still there with the same type;
    - webhook_delivery_spec: a body without `event` logs a warning and still posts;
    - Slack, Discord and Telegram bodies are byte-identical to 0.17.0's (REQ-11)
  - After: T1
  - Done when: `R rspec spec/lib/rails_error_dashboard/services/webhook_contract_spec.rb spec/lib/rails_error_dashboard/services/webhook_delivery_spec.rb spec/jobs/rails_error_dashboard` → 0 failures
- [x] **T3** The contract page, and a spec that keeps it complete → REQ-13, REQ-14
  - Files: docs/WEBHOOKS.md, _reference/webhooks.md, docs/API_REFERENCE.md, _reference/api-reference.md, spec/docs/webhooks_contract_doc_spec.rb
  - Test: webhooks_contract_doc_spec:
    - every value in `Webhooks::EVENTS` appears on `docs/WEBHOOKS.md` with an example body;
    - the page names every top-level body key from the T2 contract spec's bodies, and every
      header;
    - the page states the 1.x promise
  - After: T2
  - Done when: `R rspec spec/docs/webhooks_contract_doc_spec.rb` → 0 failures
- [ ] **T4** Upgrade notes and the notifications guide show v1 → REQ-15
  - Files: docs/UPGRADING.md, _getting_started/upgrading.md, docs/guides/NOTIFICATIONS.md, _guides/notifications.md, docs/guides/CONFIGURATION.md, _guides/configuration.md, spec/docs/webhooks_contract_doc_spec.rb
  - Test: webhooks_contract_doc_spec:
    - both UPGRADING copies have a 0.18.0 section naming the three renames, `version`, `timestamp`
      and the headers;
    - no page under `docs/`, `_guides/` or `_getting_started/` names an old event outside
      UPGRADING
  - After: T3
  - Done when: `R rspec spec/docs/webhooks_contract_doc_spec.rb` → 0 failures
