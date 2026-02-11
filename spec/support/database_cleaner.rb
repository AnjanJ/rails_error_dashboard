# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    if example.metadata[:type] == :system
      # System specs use Rails transactional fixtures (Cuprite shares the AR connection)
      example.run
    else
      DatabaseCleaner.cleaning do
        example.run
      end
    end
  end
end
