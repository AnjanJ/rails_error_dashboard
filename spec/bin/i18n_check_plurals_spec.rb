# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "open3"

# Regression cover for bin/i18n-check's plural-group detection.
#
# The script is a standalone build tool with hard-coded ROOT/LOCALES_DIR
# constants, so these examples copy it into a throwaway root and run it there as
# a subprocess. That tests the shipped script unmodified, and — deliberately —
# never writes a locale file into the engine's own config/locales. Doing that
# trips the file-watcher hazard documented in spec/support/locale_fixtures.rb
# and breaks unrelated model specs.
RSpec.describe "bin/i18n-check plural detection" do
  # A source with one real plural group, plus a non-plural sibling so parity
  # has something ordinary to compare too.
  SOURCE_YAML = <<~YAML
    en:
      red:
        items:
          one: "1 item"
          other: "%{count} items"
        title: "Hello"
  YAML

  def run_check(locales)
    Dir.mktmpdir("i18n-check-spec") do |root|
      FileUtils.mkdir_p(File.join(root, "bin"))
      FileUtils.mkdir_p(File.join(root, "config", "locales"))
      FileUtils.cp(
        RailsErrorDashboard::Engine.root.join("bin", "i18n-check").to_s,
        File.join(root, "bin", "i18n-check")
      )
      locales.each do |name, body|
        File.write(File.join(root, "config", "locales", "#{name}.yml"), body)
      end

      stdout, _stderr, status = Open3.capture3(
        RbConfig.ruby, File.join(root, "bin", "i18n-check"), "--quiet"
      )
      [ status.exitstatus, stdout ]
    end
  end

  # The bug this exists to prevent. Japanese and Chinese have `other` ALONE.
  # Detecting plural groups by counting the TARGET's children needs two or more
  # to recognise a group, so a correct ja.yml collapsed to a single `other`
  # stopped being seen as plural: parity then reported the parent missing AND
  # the `.other` leaf orphaned. Every one of RED's 67 plural groups failed that
  # way, making a correct Japanese locale unshippable.
  #
  # This is the mirror of the French `many` case: the parity exemption has to be
  # symmetric for locales with FEWER categories than English as well as more.
  describe "a locale whose CLDR rules give it `other` alone" do
    it "accepts a correct other-only locale" do
      status, output = run_check(
        "en" => SOURCE_YAML,
        "ja" => <<~YAML
          ja:
            red:
              items:
                other: "%{count}件"
              title: "こんにちは"
        YAML
      )

      expect(output).not_to match(/red\.items/)
      expect(status).to eq(0), "an other-only locale must pass:\n#{output}"
    end
  end

  # The fix must not buy Japanese in by making the checker blind. Anchoring
  # group detection to the source narrows what counts as a plural group; it must
  # not narrow what counts as a defect.
  describe "defects that must still fail for an other-only locale" do
    it "fails when a plural group is dropped wholesale" do
      status, output = run_check(
        "en" => SOURCE_YAML,
        "ja" => "ja:\n  red:\n    title: \"こんにちは\"\n"
      )

      expect(output).to include("red.items")
      expect(status).to eq(1)
    end

    it "fails when the locale supplies a category its CLDR rules forbid" do
      status, output = run_check(
        "en" => SOURCE_YAML,
        "ja" => <<~YAML
          ja:
            red:
              items:
                one: "1件"
                other: "%{count}件"
              title: "こんにちは"
        YAML
      )

      expect(output).to include("category one is not valid for 'ja'")
      expect(status).to eq(1)
    end

    it "fails when an other-only form drops an interpolation variable" do
      status, output = run_check(
        "en" => SOURCE_YAML,
        "ja" => <<~YAML
          ja:
            red:
              items:
                other: "件"
              title: "こんにちは"
        YAML
      )

      expect(output).to include("interpolation mismatch")
      expect(status).to eq(1)
    end
  end

  # The `all children are plural categories` rule stays load-bearing:
  # red.errors.index.filters.frequencies has a child named `few` that is a
  # filter label, not a plural form.
  describe "a node with a plural-looking child that is not a plural group" do
    it "does not treat it as a plural group in either locale" do
      source = <<~YAML
        en:
          red:
            frequencies:
              once: "Once"
              few: "2-9 Times"
      YAML

      status, output = run_check(
        "en" => source,
        "ja" => "ja:\n  red:\n    frequencies:\n      once: \"1回\"\n      few: \"2〜9回\"\n"
      )

      expect(output).not_to include("not valid for 'ja'")
      expect(status).to eq(0), output
    end
  end
end
