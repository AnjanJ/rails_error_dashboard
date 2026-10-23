# frozen_string_literal: true

require "rails_helper"

# Every file the dashboard's layout loads from a CDN is pinned: an npm package
# at an exact version (immutable on jsDelivr; a generated .min file or a git
# tag is not), and a copy in spec/support/vendor/ that its integrity hash is
# checked against. A version bump that changes only half of that fails here.
#
# Live updates are on, so the live-updates client (#308) is checked too.
RSpec.describe "CDN files in the dashboard layout", type: :request do
  let(:vendor_dir) { File.expand_path("../support/vendor", __dir__) }

  before do
    RailsErrorDashboard.configuration.authenticate_with = -> { true }
    allow(RailsErrorDashboard::Services::ErrorBroadcaster).to receive(:available?).and_return(true)
  end

  after { RailsErrorDashboard.configuration.authenticate_with = nil }

  # [tag, url] for every off-site script and stylesheet on a dashboard page.
  def off_site_tags
    get "/error_dashboard/errors"
    expect(response).to have_http_status(:ok)

    Nokogiri::HTML(response.body).css("script[src], link[rel~='stylesheet'][href]").filter_map do |tag|
      url = tag["src"] || tag["href"]
      [ tag, url ] if url.match?(%r{\A(https?:)?//})
    end
  end

  def jsdelivr_tags
    off_site_tags.select { |_tag, url| url.start_with?("https://cdn.jsdelivr.net/") }
  end

  def vendored_copy(url)
    File.join(vendor_dir, File.basename(URI.parse(url).path))
  end

  # host-hygiene-0-17/REQ-6
  it "loads every jsDelivr file from an npm package at an exact version" do
    urls = jsdelivr_tags.map(&:last)

    expect(urls.size).to eq(10)
    expect(urls).to all(match(%r{\Ahttps://cdn\.jsdelivr\.net/npm/(@[\w.-]+/)?[\w.-]+@\d+\.\d+\.\d+/\S+\z}))
  end

  # host-hygiene-0-17/REQ-7
  it "keeps a copy of every jsDelivr file in spec/support/vendor" do
    jsdelivr_tags.each do |_tag, url|
      expect(File).to exist(vendored_copy(url)), "no vendored copy of #{url}"
    end
  end
end
