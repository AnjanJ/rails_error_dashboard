# Vendored CDN files

A byte-for-byte copy of every file the dashboard's layout loads from jsDelivr.
They serve two purposes:

- **Pinning.** Each layout tag carries an `integrity` hash, and
  `spec/requests/cdn_integrity_spec.rb` checks every hash against the copy here.
  A version bump that changes the URL, the hash or the copy alone fails there.
- **Offline system specs (#183).** The scripts the system specs execute are
  served from here instead of the network (`VENDORED_SCRIPTS` in
  `spec/support/capybara.rb`), under the same integrity check a browser applies
  in production. Everything else the layout loads is aborted by the interceptor.

Each file is the one its npm package publishes at that exact version. jsDelivr
also generates files a package doesn't ship (a `.min.js` or `.min.css` it
minifies itself), and those bytes can change without a version bump, so the
layout never uses one. Check a file's presence with
`https://data.jsdelivr.com/v1/packages/npm/<package>@<version>?structure=flat`.

| File | Package | Executed by system specs |
|---|---|---|
| `bootstrap-icons.min.css` | `bootstrap-icons@1.11.3` (`font/`) | no |
| `chart.umd.js` | `chart.js@4.4.0` (`dist/`) | yes: `chart_date_locale_spec` asks Chart.js what it drew (#178) |
| `chartjs-adapter-date-fns.bundle.min.js` | `chartjs-adapter-date-fns@3.0.0` (`dist/`) | yes: the adapter #178 patches |
| `chartkick.min.js` | `chartkick@5.0.1` (`dist/`) | yes: wraps Chart.js for the dashboard's charts |
| `catppuccin-mocha.css` | `@catppuccin/highlightjs@1.0.0` (`css/`) | no |
| `highlight.min.js` | `@highlightjs/cdn-assets@11.9.0` | no |
| `highlightjs-line-numbers.min.js` | `highlightjs-line-numbers.js@2.8.0` (`dist/`) | no |
| `bootstrap.bundle.min.js` | `bootstrap@5.3.0` (`dist/js/`) | yes: `wait_for_page_load` blocks on `window.bootstrap` for every system spec |
| `stimulus.umd.js` | `@hotwired/stimulus@3.2.2` (`dist/`) | no |
| `turbo.js` | `@hotwired/turbo-rails@8.0.23` (`app/assets/javascripts/`) | yes: `live_updates_spec`; its hash is also pinned in `application_helper.rb` |

## Updating a file

1. Change the URL in `app/views/layouts/rails_error_dashboard.html.erb` (for
   `turbo.js`, `LIVE_UPDATES_CLIENT_URL` in
   `app/helpers/rails_error_dashboard/application_helper.rb`).
2. Download the file the URL names into this folder, under its own file name:

   ```bash
   cd spec/support/vendor
   curl -sfO https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.js
   ```

3. Put its hash in the tag's `integrity` attribute (for `turbo.js`, in
   `LIVE_UPDATES_CLIENT_INTEGRITY`):

   ```bash
   echo "sha384-$(openssl dgst -sha384 -binary chart.umd.js | openssl base64 -A)"
   ```

4. Run `spec/requests/cdn_integrity_spec.rb` and the system specs.
   `bin/pre-release-test release_audit` also compares every hash with the live
   CDN.

The URL patterns in `capybara.rb` match **any** version, so a bump keeps being
served from here rather than silently falling through to an abort, which would
turn assertions into skips instead of failures.
