# frozen_string_literal: true

# The identity fields the storm gate buffers for an error: v2 as
# opaque_identity, v1 beside it (hardening-1-0-rc2/REQ-5). Taken from the gate
# itself, so a hand-built entry flushes as a real one would.
#
# An entry built without them has rc.1's shape: its identity is recomputed
# from the parts with the v1 recipe, and it is counted under v1 alone
# (hardening-1-0-rc2/REQ-6), so it no longer reaches a group created since.
module StormEntryIdentity
  def self.for(error, context = {})
    parts = RailsErrorDashboard::Services::StormProtection::Gate.send(:gate_parts, error, context)
    { "opaque_identity" => parts[:opaque_identity], "opaque_identity_v1" => parts[:opaque_identity_v1] }
  end
end
