# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The versioning policy" do
  root = RailsErrorDashboard::Engine.root
  let(:policy) { root.join("docs/VERSIONING.md").read.gsub(/\s+/, " ") }
  let(:security) { root.join("SECURITY.md").read }

  it "says SemVer applies from 1.0.0 (public-api-and-policies/REQ-4)" do
    expect(policy).to match(/SemVer|Semantic Versioning/).and include("1.0.0")
  end

  it "says how long a deprecation warns, and when it can go (public-api-and-policies/REQ-4)" do
    expect(policy).to match(/at least two minor/).and match(/only in a major/)
    expect(policy).to match(/last minor before a major warns/)
  end

  it "says minimums rise only at a major (public-api-and-policies/REQ-4)" do
    expect(policy).to match(/Rails and Ruby minimums rise only at a major/)
  end

  it "says what a minor's migrations are (public-api-and-policies/REQ-4)" do
    expect(policy).to match(/additive/).and match(/safe to run twice/)
  end

  it "says who gets security fixes (public-api-and-policies/REQ-4)" do
    expect(policy).to match(/current major/).and match(/previous major's last minor/)
  end

  it "gives 0.x its window (public-api-and-policies/REQ-4)" do
    expect(policy).to match(/security fixes only, on its last minor, until 2027-06-30/)
  end

  it "has a SECURITY.md table that says the same (public-api-and-policies/REQ-5)" do
    table = security[/## Supported Versions.*?(?=^## )/m].to_s

    expect(table).to include("previous major's last minor", "2027-06-30", "VERSIONING.md")
    expect(table).not_to match(/current version only/)
    expect(table).not_to match(/< Latest/)
  end

  it "is linked from the README, with the public API page (public-api-and-policies/REQ-6)" do
    expect(root.join("README.md").read).to include("docs/PUBLIC_API.md", "docs/VERSIONING.md")
  end
end
