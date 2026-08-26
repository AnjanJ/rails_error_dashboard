# Vendored test assets

These are the CDN scripts the system specs actually **execute**, kept here so
the suite never touches the network (#183).

| File | Layout tag | Why it must run |
|---|---|---|
| `bootstrap.bundle.min.js` | `bootstrap@5.3.0` | `wait_for_page_load` blocks on `window.bootstrap` for *every* system spec; the modal specs need real Bootstrap behaviour |
| `chart.umd.min.js` | `chart.js@4.4.0` | `chart_date_locale_spec` asks Chart.js what it drew, to verify the localized date adapter (#178) |
| `chartjs-adapter-date-fns.bundle.min.js` | `chartjs-adapter-date-fns@3.0.0` | the adapter that fix patches |
| `chartkick.min.js` | `chartkick@5.0.1` | wraps Chart.js for the dashboard's charts |

Everything else the layout loads — icon fonts, webfonts, highlight.js,
Stimulus — is decorative, asserted on by no spec, and simply aborted by the
interceptor in `spec/support/capybara.rb`.

## Updating

If a `<script>` tag in `app/views/layouts/rails_error_dashboard.html.erb` is
bumped, re-download the matching file so the specs exercise what production
ships:

```bash
cd spec/support/vendor
curl -sO https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js
curl -s https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js -o chart.umd.min.js
curl -s https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns@3.0.0/dist/chartjs-adapter-date-fns.bundle.min.js -o chartjs-adapter-date-fns.bundle.min.js
curl -s https://cdn.jsdelivr.net/npm/chartkick@5.0.1/dist/chartkick.min.js -o chartkick.min.js
```

The URL patterns in `capybara.rb` match **any** version, so a bump keeps being
served from here rather than silently falling through to an abort — which would
turn assertions into skips instead of failures.
