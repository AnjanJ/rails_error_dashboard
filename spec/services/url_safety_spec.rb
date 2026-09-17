# frozen_string_literal: true

require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::UrlSafety do
  describe ".http_url?" do
    [
      "https://github.com/a/b/issues/1",
      "http://git.internal/a/b/issues/1",
      "HTTPS://GITHUB.COM/a/b/issues/1",
      "https://gitlab.example.com:8443/a/b/-/issues/2?x=1#note_3",
      "https://[::1]/issues/1"
    ].each do |url|
      it "accepts #{url}" do
        expect(described_class.http_url?(url)).to be true
      end
    end

    {
      "nil" => nil,
      "a non-string" => 42,
      "an empty string" => "",
      "javascript:" => "javascript:alert(1)",
      "mixed-case javascript:" => "JaVaScRiPt:alert(1)",
      "javascript: split by a TAB" => "java\tscript:alert(1)",
      "javascript: split by a newline" => "java\nscript:alert(1)",
      "a leading space" => " https://github.com/a/b/issues/1",
      "a trailing newline" => "https://github.com/a/b/issues/1\n",
      "an embedded NUL" => "https://github.com/\0a",
      "data:" => "data:text/html,<script>alert(1)</script>",
      "vbscript:" => "vbscript:x",
      "file:" => "file:///etc/passwd",
      "ftp:" => "ftp://h/issues/1",
      "mailto:" => "mailto:a@b.test",
      "a protocol-relative URL" => "//evil.example/issues/1",
      "a relative path" => "/relative/issues/1",
      "a bare host" => "github.com/a/b/issues/1",
      "https with no host" => "https://",
      "https with an empty authority" => "https:///path",
      "a scheme-only lookalike" => "https:javascript:alert(1)",
      "an unparseable URL" => "https://exa<mple.com/",
      "invalid UTF-8 bytes" => "https://github.com/\xFF\xFE".dup.force_encoding("UTF-8")
    }.each do |label, value|
      it "rejects #{label}" do
        expect(described_class.http_url?(value)).to be false
      end
    end

    it "never raises, whatever it is given" do
      [ Object.new, [], {}, :sym, "\xC3".b, "https://" + ("a" * 100_000) ].each do |value|
        expect { described_class.http_url?(value) }.not_to raise_error
      end
    end
  end
end
