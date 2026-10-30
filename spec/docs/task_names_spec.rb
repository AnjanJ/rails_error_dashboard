# frozen_string_literal: true

require "rails_helper"
require "open3"

# Decision 0008: one rake namespace. Old names stay only where they're defined,
# and where upgraders need them.
RSpec.describe "Names in the code and docs" do
  root = RailsErrorDashboard::Engine.root
  names = %w[
    verify list_applications backfill_application app_stats cleanup_resolved diagnostic_dump
    retention_cleanup scrub_invalid_encoding backfill_resolved_at digest_session_ids send_digest
  ]
  upgrading = %w[docs/UPGRADING.md _getting_started/upgrading.md]
  searched = Dir.glob(root.join("{app,lib,config/locales,docs,_guides,_reference,_getting_started,_features}/**/*.{rb,erb,rake,yml,md}"))
    .push(root.join("README.md").to_s)
    .map { |file| Pathname(file).relative_path_from(root).to_s }

  define_method(:naming) do |pattern, except:|
    (searched - except).select { |file| File.read(root.join(file)).match?(pattern) }
  end

  it "names only rails_error_dashboard: tasks, apart from UPGRADING and the aliases (deprecations-0-18/REQ-12)" do
    old_task = /(?<![_a-z])error_dashboard:(?:#{names.join('|')})\b/

    expect(naming(old_task, except: upgrading + %w[lib/tasks/error_dashboard.rake])).to be_empty
  end

  it "offers USE_SEPARATE_ERROR_DB nowhere (deprecations-0-18/REQ-15)" do
    # UNINSTALL lists it among the variables to remove, which is still right.
    pages = searched.grep(/\.md\z/) - upgrading - %w[docs/UNINSTALL.md _reference/uninstall.md]

    expect(pages.select { |file| File.read(root.join(file)).include?("USE_SEPARATE_ERROR_DB") }).to be_empty
  end

  it "documents neither dead option (deprecations-0-18/REQ-8)" do
    pages = searched.grep(/\.md\z/) - upgrading

    expect(pages.select { |file| File.read(root.join(file)).match?(/async_adapter|llm_observability_content_capture/) }).to be_empty
  end

  it "keeps no label for the Settings row that went (deprecations-0-18/REQ-9)" do
    expect(Dir.glob(root.join("config/locales/*.yml")).select { |file| File.read(file).match?(/^\s+async_adapter:/) }).to be_empty
  end

  it "passes the locale checker (deprecations-0-18/REQ-12)" do
    output, status = Open3.capture2e(RbConfig.ruby, root.join("bin/i18n-check").to_s, chdir: root.to_s)

    expect(status).to be_success, output
  end
end
