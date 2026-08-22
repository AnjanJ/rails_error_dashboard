# frozen_string_literal: true

require "rails_helper"
require "open3"
require "json"
require "tmpdir"

# P3-T2 REQ-6: `en` output must be identical, character for character, to the
# hardcoded-array implementation this replaced.
#
# Asserting that from Ruby is not possible — the functions are JavaScript, live
# inside the layout's IIFE, and are not exposed on window. Driving them through
# Capybara can only reach the handful of timestamps a page happens to render.
# So this extracts the date block from the layout, loads it in node with a
# stubbed window, and compares every directive across a full year of dates and
# every relative-time threshold.
#
# node is already required by this suite (Cuprite drives headless Chrome), so
# this adds no dependency. It skips rather than fails if node is absent.
RSpec.describe "JS date localization parity", type: :system do
  # The pre-P3-T2 implementation, kept verbatim as the reference. If this ever
  # needs to change, `en` output has changed and REQ-6 is broken.
  ENGLISH_REFERENCE = <<~JS
    function formatDateTime(date, fmt) {
      var months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
      var monthsShort = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      var days = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
      var daysShort = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
      var y = date.getFullYear(), mo = date.getMonth(), d = date.getDate();
      var h = date.getHours(), mi = date.getMinutes(), s = date.getSeconds(), dow = date.getDay();
      var h12 = h % 12 || 12, ampm = h >= 12 ? 'PM' : 'AM';
      var pad = function(n) { return n.toString().padStart(2, '0'); };
      return fmt.replace('%Y',y).replace('%y',y.toString().substr(2)).replace('%B',months[mo]).replace('%b',monthsShort[mo])
        .replace('%m',pad(mo+1)).replace('%d',pad(d)).replace('%e',d).replace('%A',days[dow]).replace('%a',daysShort[dow])
        .replace('%H',pad(h)).replace('%I',pad(h12)).replace('%M',pad(mi)).replace('%S',pad(s)).replace('%p',ampm).replace('%P',ampm.toLowerCase());
    }

    function formatRelativeTime(diffMs) {
      var sec = Math.floor(diffMs / 1000), min = Math.floor(sec / 60), hr = Math.floor(min / 60), d = Math.floor(hr / 24), mo = Math.floor(d / 30), yr = Math.floor(d / 365);
      if (sec < 60) return sec <= 1 ? '1 second ago' : sec + ' seconds ago';
      if (min < 60) return min === 1 ? '1 minute ago' : min + ' minutes ago';
      if (hr < 24) return hr === 1 ? '1 hour ago' : hr + ' hours ago';
      if (d < 30) return d === 1 ? '1 day ago' : d + ' days ago';
      if (mo < 12) return mo === 1 ? '1 month ago' : mo + ' months ago';
      return yr === 1 ? '1 year ago' : yr + ' years ago';
    }
  JS

  # The localized implementation, lifted out of the layout so it runs outside
  # a browser. Bounded by the two comments that bracket it in the template.
  def localized_source
    layout = Rails.root.join("../../app/views/layouts/rails_error_dashboard.html.erb").cleanpath
    layout = RailsErrorDashboard::Engine.root.join("app/views/layouts/rails_error_dashboard.html.erb") unless layout.exist?
    body = File.read(layout)

    start_at = body.index("  // English defaults for every localized value below.")
    stop_at = body.index("  convertToLocalTime();", start_at.to_i)

    raise "could not locate the date block in the layout" if start_at.nil? || stop_at.nil?

    body[start_at...stop_at]
  end

  def en_payload
    {
      "locale" => "en",
      "js" => RailsErrorDashboard::I18nStore.subtree("red.js", locale: "en"),
      "formats" => RailsErrorDashboard::I18nStore.subtree("red.time.formats", locale: "en"),
      "ago" => RailsErrorDashboard::I18nStore.translate("red.time.ago", locale: "en")
    }
  end

  # Runs `script` in node with both implementations loaded as `oldApi` and
  # `newApi`, and RED_I18N set to `payload`. Returns the parsed JSON it prints.
  def in_node(payload, script)
    harness = <<~JS
      const REF = (function() {
        #{ENGLISH_REFERENCE}
        return { formatDateTime: formatDateTime, formatRelativeTime: formatRelativeTime };
      })();
      function build(payload) {
        const fn = new Function('window', 'document', #{localized_source.to_json} + `
          return { formatDateTime: formatDateTime, formatRelativeTime: formatRelativeTime, getTimezoneAbbreviation: getTimezoneAbbreviation };
        `);
        return fn({ RED_I18N: payload }, { querySelectorAll: function() { return { forEach: function() {} }; } });
      }
      const oldApi = REF;
      const newApi = build(#{payload.to_json});
      #{script}
    JS

    Dir.mktmpdir do |dir|
      path = File.join(dir, "parity.js")
      File.write(path, harness)
      out, err, status = Open3.capture3("node", path)
      raise "node failed: #{err}" unless status.success?

      JSON.parse(out)
    end
  end

  before do
    skip "node is not available" unless system("which node > /dev/null 2>&1")
  end

  describe "English parity (REQ-6)" do
    it "renders every directive identically across a full year of dates" do
      result = in_node(en_payload, <<~JS)
        const fmts = ['%B %d, %Y %I:%M:%S %p','%m/%d %I:%M%p','%B %d, %Y','%I:%M:%S %p','%b %d, %Y %H:%M','%A %a %e %y %H:%M %P'];
        const diffs = [];
        let checked = 0;
        for (let m = 0; m < 12; m++) {
          for (let d = 1; d <= 28; d += 9) {
            for (const h of [0, 1, 11, 12, 13, 23]) {
              const date = new Date(Date.UTC(2026, m, d, h, 7, 5));
              for (const f of fmts) {
                checked++;
                const a = oldApi.formatDateTime(date, f);
                const b = newApi.formatDateTime(date, f);
                if (a !== b) diffs.push({ fmt: f, iso: date.toISOString(), old: a, new: b });
              }
            }
          }
        }
        console.log(JSON.stringify({ checked: checked, diffs: diffs }));
      JS

      expect(result["checked"]).to be > 1000
      expect(result["diffs"]).to be_empty,
        "en output changed in #{result["diffs"].size} cases, e.g. #{result["diffs"].first(3)}"
    end

    it "renders every relative-time threshold identically" do
      result = in_node(en_payload, <<~JS)
        const S = 1000, M = 60 * S, H = 60 * M, D = 24 * H;
        const cases = [0, 1*S, 1.5*S, 30*S, 59*S, 60*S, 5*M, 59*M, 1*H, 2*H, 23*H, 1*D, 5*D, 29*D, 30*D, 60*D, 364*D, 365*D, 3*365*D];
        const diffs = [];
        for (const ms of cases) {
          const a = oldApi.formatRelativeTime(ms);
          const b = newApi.formatRelativeTime(ms);
          if (a !== b) diffs.push({ ms: ms, old: a, new: b });
        }
        console.log(JSON.stringify({ checked: cases.length, diffs: diffs }));
      JS

      expect(result["diffs"]).to be_empty,
        "relative time changed: #{result["diffs"]}"
    end
  end

  # REQ-1/2/3. A locale that actually differs from English must come through —
  # otherwise parity above could be satisfied by ignoring the payload entirely.
  describe "a translated locale (de)" do
    let(:de_payload) do
      {
        "locale" => "de",
        "js" => {
          "months" => %w[Januar Februar März April Mai Juni Juli August September Oktober November Dezember],
          "months_short" => %w[Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez],
          "days" => %w[Sonntag Montag Dienstag Mittwoch Donnerstag Freitag Samstag],
          "days_short" => %w[So Mo Di Mi Do Fr Sa],
          # A 24-hour locale legitimately has no meridian text.
          "meridian" => { "am" => "", "pm" => "" },
          "intl_locale" => "de-DE",
          "duration" => {
            "minutes" => { "one" => "1 Minute", "other" => "%{count} Minuten" },
            "days" => { "one" => "1 Tag", "other" => "%{count} Tagen" }
          }
        },
        "formats" => { "full" => "%d. %B %Y %H:%M:%S", "date_only" => "%d. %B %Y" },
        "ago" => "vor %{duration}"
      }
    end

    it "renders German month names in German date order" do
      result = in_node(de_payload, <<~JS)
        const d = new Date(Date.UTC(2026, 2, 9, 14, 5, 3));
        console.log(JSON.stringify({
          date_only: newApi.formatDateTime(d, '%d. %B %Y'),
          weekday: newApi.formatDateTime(d, '%A'),
          short: newApi.formatDateTime(d, '%b')
        }));
      JS

      expect(result["date_only"]).to eq("09. März 2026")
      expect(result["weekday"]).to eq("Montag")
      expect(result["short"]).to eq("Mär")
    end

    # The reason "ago" is a template and not a suffix: German puts it first.
    it "places the ago template around the duration rather than after it" do
      result = in_node(de_payload, <<~JS)
        console.log(JSON.stringify({
          minutes: newApi.formatRelativeTime(5 * 60 * 1000),
          one_minute: newApi.formatRelativeTime(60 * 1000),
          days: newApi.formatRelativeTime(5 * 24 * 3600 * 1000)
        }));
      JS

      expect(result["minutes"]).to eq("vor 5 Minuten")
      expect(result["one_minute"]).to eq("vor 1 Minute")
      expect(result["days"]).to eq("vor 5 Tagen")
    end

    it "renders no AM/PM for a 24-hour locale, and never the string undefined" do
      result = in_node(de_payload, <<~JS)
        const d = new Date(Date.UTC(2026, 2, 9, 14, 5, 3));
        console.log(JSON.stringify({ out: newApi.formatDateTime(d, '%H:%M %p') }));
      JS

      expect(result["out"]).not_to include("undefined")
      expect(result["out"]).not_to include("PM")
    end
  end

  # REQ-3. Not every language has English's one/other split.
  describe "a locale with a single plural category (REQ-3)" do
    it "uses :other at count 1 rather than rendering undefined" do
      payload = {
        "locale" => "ja",
        "js" => { "duration" => { "seconds" => { "other" => "%{count}秒" }, "minutes" => { "other" => "%{count}分" } } },
        "ago" => "%{duration}前"
      }

      result = in_node(payload, <<~JS)
        console.log(JSON.stringify({
          one: newApi.formatRelativeTime(1000),
          many: newApi.formatRelativeTime(5 * 60 * 1000)
        }));
      JS

      expect(result["one"]).to eq("1秒前")
      expect(result["many"]).to eq("5分前")
    end
  end

  # REQ-7. A cached page or an earlier JS error must not put "undefined" into
  # every timestamp on the page.
  describe "degradation (REQ-7)" do
    it "falls back to English when RED_I18N is absent or malformed" do
      result = in_node(nil, <<~JS)
        const d = new Date(Date.UTC(2026, 2, 9, 14, 5, 3));
        const malformed = [
          { js: { months: 'not-an-array' } },
          { js: { months: ['too', 'short'] } },
          { js: { meridian: 'nope' } },
          { js: { duration: { seconds: null } } },
          { js: null },
          {}
        ];
        const outputs = [];
        for (const payload of malformed) {
          const api = build(payload);
          outputs.push(api.formatDateTime(d, '%B %d, %Y %p') + '|' + api.formatRelativeTime(1000));
        }
        console.log(JSON.stringify({
          absent_date: newApi.formatDateTime(d, '%B %d, %Y'),
          absent_relative: newApi.formatRelativeTime(5 * 60 * 1000),
          malformed: outputs
        }));
      JS

      expect(result["absent_date"]).to eq("March 09, 2026")
      expect(result["absent_relative"]).to eq("5 minutes ago")

      result["malformed"].each do |output|
        expect(output).not_to include("undefined")
        expect(output).to include("March 09, 2026")
      end
    end
  end
end
