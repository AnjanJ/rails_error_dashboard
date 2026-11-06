# frozen_string_literal: true

require "yaml"
require_relative "../../benchmark/load/stacks"

# What compose makes of a stack's files, read without Docker: each file laid
# over the one before it, a mapping merged key by key and anything else
# replaced, which is how compose merges the parts these files use. Required by
# the specs that read a stack; it sits here, not in spec/support/, because
# spec_helper requires everything under spec/support/ into the suite.
module ComposeFiles
  module_function

  def merged(stack)
    stack.compose_files.map { |file| YAML.load_file(File.join(RedBenchmark::Load::Stacks::LOAD, file)) }
      .reduce { |under, over| merge(under, over) }
  end

  def merge(under, over)
    under.merge(over) { |_key, a, b| a.is_a?(Hash) && b.is_a?(Hash) ? merge(a, b) : b }
  end
end
