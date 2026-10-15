# frozen_string_literal: true

require "rails_helper"

# The whole point of boot-crash capture is WHEN the at_exit hook is
# registered. If this initializer ever drifts behind :eager_load!, a
# Zeitwerk::NameError kills the process before the hook exists and nothing
# is captured, exactly the gap this spec pins.
RSpec.describe "engine initializer order" do
  let(:names) { Rails.application.initializers.tsort_each.map(&:name) }

  it "registers the crash-capture hook after the host's initializers and before eager loading" do
    crash = names.index("rails_error_dashboard.crash_capture")
    eager = names.index(:eager_load!)
    config = names.rindex(:load_config_initializers)

    expect(crash).not_to be_nil
    expect(crash).to be < eager
    expect(crash).to be > names.index(:load_config_initializers)
    expect(config).to be < eager
  end
end
