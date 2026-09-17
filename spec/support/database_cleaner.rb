# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    # Examples that need rows COMMITTED, because other connections must see
    # them (a cross-connection race). Same treatment as :migration below; the
    # group also sets `self.use_transactional_tests = false`.
    if example.metadata[:non_transactional]
      example.run
      DatabaseCleaner.clean_with(:deletion)
      next
    end

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
