# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::ApplicationHelper, type: :helper do
  describe "#safe_external_url" do
    it "returns an http(s) URL unchanged" do
      expect(helper.safe_external_url("https://x.test/a")).to eq("https://x.test/a")
      expect(helper.safe_external_url("http://x.test/a")).to eq("http://x.test/a")
    end

    [ nil, "", "javascript:x", "JAVASCRIPT:x", "data:text/html,x", "//x", "/x", " https://x.test/a", 42 ].each do |value|
      it "returns nil for #{value.inspect}" do
        expect(helper.safe_external_url(value)).to be_nil
      end
    end
  end

  describe "#safe_label_color" do
    it "accepts 6- and 3-digit hex, with or without a leading #" do
      expect(helper.safe_label_color("d73a4a")).to eq("#d73a4a")
      expect(helper.safe_label_color("#D73A4A")).to eq("#D73A4A")
      expect(helper.safe_label_color("fff")).to eq("#fff")
    end

    [ nil, "", 123, "red", "fffff", "fffffff", "d73a4a;position:fixed", "d73a4a\n", "url(x)", "ggg" ].each do |value|
      it "falls back to grey for #{value.inspect}" do
        expect(helper.safe_label_color(value)).to eq("#6c757d")
      end
    end
  end

  describe "#label_text_color" do
    it "picks black on light backgrounds and white on dark ones" do
      expect(helper.label_text_color("#fef2c0")).to eq("#000")
      expect(helper.label_text_color("#fff")).to eq("#000")
      expect(helper.label_text_color("#d73a4a")).to eq("#fff")
      expect(helper.label_text_color("#000")).to eq("#fff")
      expect(helper.label_text_color("#6c757d")).to eq("#fff")
    end

    it "returns white for anything that is not a validated colour" do
      expect(helper.label_text_color("nonsense")).to eq("#fff")
      expect(helper.label_text_color(nil)).to eq("#fff")
    end
  end

  describe "#extract_table_from_sql" do
    it "extracts table name from a standard SELECT query" do
      expect(helper.extract_table_from_sql('SELECT "users".* FROM "users" WHERE "users"."id" = ?')).to eq("users")
    end

    it "extracts table name from a query without quotes" do
      expect(helper.extract_table_from_sql("SELECT * FROM posts WHERE id = 1")).to eq("posts")
    end

    it "extracts table name from a query with backtick quotes" do
      expect(helper.extract_table_from_sql("SELECT * FROM `comments` WHERE post_id = 1")).to eq("comments")
    end

    it "is case-insensitive for FROM keyword" do
      expect(helper.extract_table_from_sql("select * from orders")).to eq("orders")
    end

    it "returns nil for blank input" do
      expect(helper.extract_table_from_sql(nil)).to be_nil
      expect(helper.extract_table_from_sql("")).to be_nil
    end

    it "returns nil when no FROM clause is found" do
      expect(helper.extract_table_from_sql("INSERT INTO users VALUES (1)")).to be_nil
    end
  end

  describe "#auto_link_urls" do
    before do
      RailsErrorDashboard.configuration.git_repository_url = nil
    end

    context "with blank text" do
      it "returns empty string for nil" do
        expect(helper.auto_link_urls(nil)).to eq("")
      end

      it "returns empty string for empty string" do
        expect(helper.auto_link_urls("")).to eq("")
      end
    end

    context "with plain text" do
      it "returns the text wrapped in paragraph tags" do
        result = helper.auto_link_urls("hello world")
        expect(result).to include("hello world")
      end
    end

    context "with URLs" do
      it "converts https URLs to clickable links" do
        result = helper.auto_link_urls("check https://example.com/path for details")
        expect(result).to include('href="https://example.com/path"')
        expect(result).to include('target="_blank"')
        expect(result).to include('rel="noopener noreferrer"')
      end

      it "converts http URLs to clickable links" do
        result = helper.auto_link_urls("see http://example.com")
        expect(result).to include('href="http://example.com"')
      end
    end

    context "with inline code in backticks" do
      it "highlights inline code with code tags" do
        result = helper.auto_link_urls("run `bundle install` first")
        expect(result).to include("<code")
        expect(result).to include("bundle install")
        expect(result).to include("inline-code-highlight")
      end
    end

    context "with file paths in backticks" do
      before do
        RailsErrorDashboard.configuration.git_repository_url = "https://github.com/test/repo"
      end

      it "converts file paths to GitHub links when repo URL is configured" do
        result = helper.auto_link_urls("check `app/models/user.rb` for the issue")
        expect(result).to include("https://github.com/test/repo/blob/main/app/models/user.rb")
        expect(result).to include("file-path-link")
      end

      it "does not convert file paths when no repo URL is configured" do
        RailsErrorDashboard.configuration.git_repository_url = nil
        result = helper.auto_link_urls("check `app/models/user.rb` for the issue")
        expect(result).not_to include("github.com")
        expect(result).to include("app/models/user.rb")
      end
    end

    context "with error parameter" do
      let(:error_log) { create(:error_log) }

      it "does not crash when application lacks repository_url column" do
        # This was the bug: Application model has no repository_url column,
        # calling error.application.repository_url raised NoMethodError
        expect {
          helper.auto_link_urls("some comment text", error: error_log)
        }.not_to raise_error
      end

      it "falls back to global config when application has no repository_url" do
        RailsErrorDashboard.configuration.git_repository_url = "https://github.com/test/repo"
        result = helper.auto_link_urls("see `app/models/user.rb`", error: error_log)
        expect(result).to include("https://github.com/test/repo/blob/main/app/models/user.rb")
      end

      it "works when error is passed without error parameter" do
        expect {
          helper.auto_link_urls("comment text", error: nil)
        }.not_to raise_error
      end
    end

    context "with nil error" do
      it "works without error parameter" do
        result = helper.auto_link_urls("plain text")
        expect(result).to include("plain text")
      end
    end

    context "HTML escaping in code blocks" do
      it "escapes HTML inside inline code backticks" do
        result = helper.auto_link_urls("run `<img onerror=alert(1)>` carefully")
        expect(result).to include("&lt;img")
        expect(result).not_to include("<img onerror")
      end
    end

    context "HTML escaping in plain text (XSS regression)" do
      # Regression: auto_link_urls fed its input straight into
      # simple_format(..., sanitize: false). Anything outside backticks/URLs
      # rendered as raw HTML, executing stored XSS for any user resolving an
      # error with HTML in the comment.
      it "escapes <script> tags in plain text" do
        result = helper.auto_link_urls("hello <script>alert(1)</script> world")
        expect(result).not_to include("<script>")
        expect(result).to include("&lt;script&gt;")
      end

      it "escapes <img onerror> in plain text" do
        result = helper.auto_link_urls("see <img src=x onerror=alert(1)> here")
        # The literal <img tag must NOT appear — that's the XSS vector.
        # The text "onerror=" inside escaped &lt;...&gt; is harmless plain text.
        expect(result).not_to include("<img src=x")
        expect(result).to include("&lt;img src=x onerror=alert(1)&gt;")
      end

      it "escapes ampersands in plain text" do
        result = helper.auto_link_urls("a & b")
        expect(result).to include("a &amp; b")
      end

      it "still produces clickable links for safe URLs alongside escaped HTML" do
        result = helper.auto_link_urls("visit https://example.com but beware <script>x</script>")
        expect(result).to include('href="https://example.com"')
        expect(result).to include("&lt;script&gt;")
        expect(result).not_to include("<script>")
      end
    end
  end

  describe "#js_safe_json" do
    # Defense-in-depth: ActiveSupport's to_json already escapes < and > to
    # < / > by default (escape_html_entities_in_json = true), so
    # </script> bypass via to_json is not exploitable on default Rails.
    # We add an explicit </ → <\/ replacement so the helper remains safe even
    # if a host app disables the AS default, and so the intent is auditable
    # at the call site.
    it "neutralizes </script> in string values" do
      result = helper.js_safe_json("danger </script><script>alert(1)</script>")
      expect(result).not_to include("</script>")
      expect(result).to be_html_safe
    end

    it "neutralizes </script> in nested hash values" do
      result = helper.js_safe_json({ msg: "evil </script>" })
      expect(result).not_to include("</script>")
    end

    it "returns valid JSON for nil, numbers, and booleans" do
      expect(helper.js_safe_json(nil)).to eq("null")
      expect(helper.js_safe_json(42)).to eq("42")
      expect(helper.js_safe_json(true)).to eq("true")
    end

    it "returns html_safe for direct script-body interpolation" do
      expect(helper.js_safe_json("hello").html_safe?).to be true
    end
  end

  describe "#parse_pg_timestamp" do
    # Regression: database_health_summary used Time.parse(value) which raises
    # TypeError when value is already a Time/TimeWithZone (which is what some
    # PG configs return from raw connection.select_all on timestamp columns).
    it "returns the value unchanged when given a Time" do
      time = Time.now
      expect(helper.parse_pg_timestamp(time)).to eq(time)
    end

    it "returns the value unchanged when given a TimeWithZone" do
      time = Time.zone.now
      expect(helper.parse_pg_timestamp(time)).to eq(time)
    end

    it "parses an ISO8601 string into a Time" do
      result = helper.parse_pg_timestamp("2026-05-03 12:00:00 UTC")
      expect(result).to be_a(Time)
      expect(result.year).to eq(2026)
    end

    it "returns nil for nil input" do
      expect(helper.parse_pg_timestamp(nil)).to be_nil
    end

    it "returns nil for blank input" do
      expect(helper.parse_pg_timestamp("")).to be_nil
    end

    it "returns nil for an unparseable string instead of raising" do
      expect(helper.parse_pg_timestamp("not a date")).to be_nil
    end
  end

  describe "#safe_parse_time" do
    it "parses an ISO 8601 string" do
      expect(helper.safe_parse_time("2026-01-02T03:04:05Z")).to eq(Time.utc(2026, 1, 2, 3, 4, 5))
    end

    it "passes a Time through" do
      time = Time.utc(2026, 1, 2)
      expect(helper.safe_parse_time(time)).to equal(time)
    end

    [ nil, "", "   ", "not a date", "2026-99-99T99:99:99Z", 12_345, 1.5, :sym, [], { "a" => 1 }, Object.new ].each do |value|
      it "returns nil for #{value.inspect[0, 40]} without raising" do
        expect(helper.safe_parse_time(value)).to be_nil
      end
    end
  end
end
