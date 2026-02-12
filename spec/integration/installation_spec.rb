# frozen_string_literal: true

# Installation and upgrade tests have been replaced by the pre-release
# chaos test suite: bin/pre-release-test
#
# The chaos suite creates real Rails apps from scratch, runs the generator,
# runs migrations, and exercises the full gem in production mode — which is
# far more realistic than what these RSpec tests attempted.
#
# See: test/pre_release/ for the full integration test suite.
