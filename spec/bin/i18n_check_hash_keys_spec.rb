# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "open3"

# bin/i18n-check's guard against translating a NAMESPACE.
#
# red_t("red.errors.sidebar.environment") names a node with children (title,
# hint, ...). I18nStore treats a Hash result as a miss and falls back to the
# humanized last segment -- "Environment" -- which is exactly right in English
# and therefore invisible, and untranslated in every other locale.
#
# Like the plural spec next door, this copies the script into a throwaway root
# and never writes into the engine's own config/locales.
RSpec.describe "bin/i18n-check namespace-key guard" do
  EN_YAML = <<~YAML
    en:
      red:
        sidebar:
          environment:
            title: "Environment"
            hint: "Runtime context"
          plain: "Plain"
        items:
          one: "1 item"
          other: "%{count} items"
  YAML

  def run_check(views: {}, helpers: {})
    Dir.mktmpdir("i18n-check-hash-spec") do |root|
      FileUtils.mkdir_p(File.join(root, "bin"))
      FileUtils.mkdir_p(File.join(root, "config", "locales"))
      FileUtils.cp(RailsErrorDashboard::Engine.root.join("bin", "i18n-check").to_s, File.join(root, "bin", "i18n-check"))
      File.write(File.join(root, "config", "locales", "en.yml"), EN_YAML)

      { "app/views/x" => views, "app/helpers" => helpers }.each do |dir, files|
        FileUtils.mkdir_p(File.join(root, dir))
        files.each { |name, body| File.write(File.join(root, dir, name), body) }
      end

      stdout, _stderr, status = Open3.capture3(RbConfig.ruby, File.join(root, "bin", "i18n-check"), "--quiet")
      [ status.exitstatus, stdout ]
    end
  end

  it "fails, naming file, line and key, when a view translates a namespace" do
    status, out = run_check(views: { "_a.html.erb" => "<p>ok</p>\n<%= red_t(\"red.sidebar.environment\") %>\n" })

    expect(status).to eq(1)
    expect(out).to include("red.sidebar.environment")
    expect(out).to include("app/views/x/_a.html.erb:2")
  end

  it "catches single-quoted keys, red_js_t, and helpers" do
    status, out = run_check(
      views: { "_b.html.erb" => "<%= red_js_t('red.sidebar.environment') %>\n" },
      helpers: { "h.rb" => "def x\n  red_t \"red.sidebar\"\nend\n" }
    )

    expect(status).to eq(1)
    expect(out).to include("app/views/x/_b.html.erb:1")
    expect(out).to include("app/helpers/h.rb:2")
  end

  it "fails when red_t (not red_tp) names a plural group" do
    status, out = run_check(views: { "_c.html.erb" => "<%= red_t(\"red.items\", count: 2) %>\n" })

    expect(status).to eq(1)
    expect(out).to include("red.items")
  end

  it "passes for leaf keys, plural groups through red_tp, dynamic keys and missing keys" do
    body = <<~ERB
      <%= red_t("red.sidebar.environment.title") %>
      <%= red_t("red.sidebar.plain") %>
      <%= red_tp("red.items", count: 2) %>
      <%= red_js_tp("red.items", count: 2) %>
      <%= red_t("red.sidebar.\#{name}", default: name) %>
      <%= red_t("red.not.defined.anywhere", default: "x") %>
    ERB

    status, out = run_check(views: { "_d.html.erb" => body })

    expect(out).not_to include("namespace")
    expect(status).to eq(0)
  end

  it "passes on the engine's own views" do
    stdout, _stderr, status = Open3.capture3(
      RbConfig.ruby, RailsErrorDashboard::Engine.root.join("bin", "i18n-check").to_s, "--quiet"
    )

    expect(stdout).not_to include("namespace-keys")
    expect(status.exitstatus).to eq(0)
  end
end
