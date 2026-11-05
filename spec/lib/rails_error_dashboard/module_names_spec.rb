# frozen_string_literal: true

require "rails_helper"

# A host app may ask every loaded class for its name, as
# ObjectSpace.each_object(Class).map(&:name) does. A RED class or module that
# replaces Ruby's own `name` makes that raise once RED is loaded.
RSpec.describe "RED's classes and modules" do
  it "answer name, called with no argument, with their own name (keep-module-name/REQ-1)" do
    RailsErrorDashboard::Engine.eager_load!
    own_name = Module.instance_method(:name)
    red = ObjectSpace.each_object(Module).select { |mod| own_name.bind_call(mod).to_s.start_with?("RailsErrorDashboard") }
    # ActiveRecord generates relation classes inside each model and names them
    # after their parents on purpose. RED doesn't define those.
    red.reject! { |mod| mod.is_a?(Class) && mod < ActiveRecord::Relation }

    wrong = red.filter_map do |mod|
      answer = begin
        mod.name
      rescue ArgumentError => e
        e
      end
      "#{own_name.bind_call(mod)} answered #{answer.inspect}" unless answer == own_name.bind_call(mod)
    end

    expect(red.map { |mod| own_name.bind_call(mod) }).to include("RailsErrorDashboard::Services::AiAgentClassifier")
    expect(wrong).to be_empty
  end
end
