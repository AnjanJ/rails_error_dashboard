# frozen_string_literal: true

# Loaded into a `bin/benchmark` subprocess through RUBYOPT by
# spec/benchmark/harness_spec.rb: any network connection the benchmark tries
# raises, so the run fails. It sits here, not in spec/support/, because
# spec_helper requires everything under spec/support/ into the suite.
require "webmock"
WebMock.enable!
WebMock.disable_net_connect!
