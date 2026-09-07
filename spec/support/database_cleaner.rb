# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    case example.metadata[:type]
    when :system
      # System specs use Rails transactional fixtures (Cuprite shares the AR connection)
      example.run
    when :migration
      # Migration specs run DDL. MySQL commits DDL implicitly, which destroys
      # the savepoint a transactional wrapper relies on and poisons the
      # connection for every example after it ("SAVEPOINT ... does not
      # exist"). So no transaction: run, then delete whatever rows were made.
      # These groups also set `self.use_transactional_tests = false`.
      example.run
      DatabaseCleaner.clean_with(:deletion)
    else
      DatabaseCleaner.cleaning do
        example.run
      end
    end
  end
end
