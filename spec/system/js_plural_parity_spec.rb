# frozen_string_literal: true

require "rails_helper"
require "open3"
require "json"
require "tmpdir"

# redPluralize only ever consulted `one` and `other`. ru, uk and pl each ship
# four CLDR categories — and their locale files have supplied `few` and `many`
# since the i18n sprint — so every relative timestamp JS renders in those
# languages picked a form the language does not use there: Russian showed
# "5 секунды" (few) where it should read "5 секунд" (many).
#
# The server has had correct rules all along, in PrivateBackend::PLURAL_RULES.
# The browser now has the same rules, and this pins the two together: a chart
# tooltip, a page timestamp and an email must agree about what five of
# something is called.
#
# Compares against the REAL backend rather than a hardcoded table, so if the
# server's rules are ever corrected this fails until the JS is corrected too.
RSpec.describe "JS plural parity", type: :system do
  # let, not a constant: a constant written inside an RSpec.describe block is
  # defined at top level, and spec/system/p7_layout_qa_spec.rb already defines
  # LOCALES. Whichever file loaded last won, and this spec silently ran against
  # the other one's four locales.

  # Every boundary the %100 guards exist for, plus the value that separates
  # Polish from Russian.
  let(:counts) { [ 0, 1, 2, 4, 5, 11, 12, 14, 21, 22, 25, 101, 111 ] }

  # The locales RED ships. de is in here deliberately: it has no entry in
  # PLURAL_RULES, so it exercises the "unlisted locale keeps one/other" path on
  # both sides.
  let(:locales) { %w[en de fr es it pt-BR pl ru uk ja zh-CN] }

  # Lifted from the layout, exactly as js_date_parity_spec does, so the shipped
  # implementation is what runs — not a copy that can drift.
  def localized_source
    layout = Rails.root.join("../../app/views/layouts/rails_error_dashboard.html.erb").cleanpath
    layout = RailsErrorDashboard::Engine.root.join("app/views/layouts/rails_error_dashboard.html.erb") unless layout.exist?
    body = File.read(layout)

    start_at = body.index("  // English defaults for every localized value below.")
    stop_at = body.index("  convertToLocalTime();", start_at.to_i)

    raise "could not locate the date block in the layout" if start_at.nil? || stop_at.nil?

    body[start_at...stop_at]
  end

  def js_categories
    script = <<~JS
      function build(locale) {
        const fn = new Function('window', 'document', #{localized_source.to_json} + `
          return { redPluralCategory: redPluralCategory };
        `);
        return fn({ RED_I18N: { locale: locale } }, { querySelectorAll: function() { return { forEach: function() {} }; } });
      }
      const out = {};
      for (const locale of #{locales.to_json}) {
        out[locale] = #{counts.to_json}.map(n => build(locale).redPluralCategory(locale, n));
      }
      console.log(JSON.stringify(out));
    JS

    Dir.mktmpdir do |dir|
      path = File.join(dir, "plural.js")
      File.write(path, script)
      out, err, status = Open3.capture3("node", path)
      raise "node failed: #{err}" unless status.success?

      JSON.parse(out)
    end
  end

  # What the real backend picks, asked the same way I18n asks it.
  def server_categories
    locales.each_with_object({}) do |locale, acc|
      backend = RailsErrorDashboard::PrivateBackend.allocate
      backend.instance_variable_set(:@current_pluralization_locale, locale)
      entry = { one: "one", few: "few", many: "many", other: "other" }
      acc[locale] = counts.map { |n| backend.send(:pluralization_key, entry, n).to_s }
    end
  end

  before do
    skip "node is not available" unless system("which node > /dev/null 2>&1")
  end

  it "picks the same plural category as the server for every locale and count" do
    expect(js_categories).to eq(server_categories)
  end

  # Called out separately because it is the mistake the server's own table
  # warns about: pl `one` is exactly 1, so 21 is `many`, while ru/uk treat any
  # count ending in 1 (except 11) as `one`. A rule copied between them looks
  # right and is wrong, and no structural check would catch it.
  it "does not treat Polish as Russian at 21" do
    js = js_categories

    expect(js["pl"][counts.index(21)]).to eq("many")
    expect(js["ru"][counts.index(21)]).to eq("one")
    expect(js["uk"][counts.index(21)]).to eq("one")
  end

  # The %100 guards. 11 looks like `one` and 12-14 look like `few` on a %10
  # reading alone, and both are `many`.
  it "applies the %100 guards for the four-category locales" do
    js = js_categories

    %w[ru uk pl].each do |locale|
      expect(js[locale][counts.index(11)]).to eq("many")
      expect(js[locale][counts.index(12)]).to eq("many")
      expect(js[locale][counts.index(14)]).to eq("many")
    end
  end
end
