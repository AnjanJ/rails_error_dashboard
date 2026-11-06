# syntax=docker/dockerfile:1
# check=error=true

# The load test's app (.shipkit/specs/deploy-shape-benchmark/, REQ-8). The first
# stage makes a new Rails app with `rails new`, which applies app/template.rb to
# add RED with its installer. From `base` down, this is the Dockerfile Rails 8.1.4
# generates for that app, except that it copies the app from the first stage
# instead of a checkout, and brings the RED checkout along. Build it through
# compose.yml and a stack's files, which pass in the RED checkout under test as
# the `red` context:
#
#   docker compose -f benchmark/load/compose.yml -f benchmark/load/stacks/postgres.yml \
#     -f benchmark/load/stacks/solid-queue.yml up --build --wait

# The Ruby the app runs on: 3.4, the default, or 4.0.
ARG RUBY_VERSION=3.4

# The stack (benchmark/load/stacks.rb): the database, as `rails new --database`
# names it, the packages Rails 8.1's generator installs for it, one the app runs
# with and one its gems build against, and the queue. A stack's files in
# stacks/ set them; these are the default stack's.
ARG DATABASE=postgresql
ARG DATABASE_PACKAGE=postgresql-client
ARG DATABASE_BUILD_PACKAGE=libpq-dev
ARG QUEUE=solid_queue

# Throw-away stage that makes the app, as a developer would on their machine
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS generate

# The Rails that generates the app. The Gemfile it writes asks for "~> 8.1.4",
# so the app runs the newest 8.1 release, as a new app would.
ARG RAILS_VERSION=8.1.4
ARG DATABASE
ARG DATABASE_BUILD_PACKAGE
# Read by app/template.rb
ARG QUEUE

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git $DATABASE_BUILD_PACKAGE libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

RUN gem install rails --version "$RAILS_VERSION" --no-document

# The RED under test, as the gem would ship it: the gemspec's files
COPY --from=red rails_error_dashboard.gemspec MIT-LICENSE Rakefile README.md /red/
COPY --from=red app /red/app
COPY --from=red config /red/config
COPY --from=red db /red/db
COPY --from=red lib /red/lib

COPY app/template.rb /template.rb
# DATABASE stays out of the generator's environment, as on a developer's
# machine: Solid Cache's installer reads it as its database's name.
RUN env -u DATABASE rails new . --name=shop --database="$DATABASE" --template=/template.rb

# The same Ruby as the stage that wrote the app's .ruby-version
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base
ARG DATABASE_PACKAGE

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips $DATABASE_PACKAGE && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build
ARG DATABASE_BUILD_PACKAGE

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git $DATABASE_BUILD_PACKAGE libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# The RED checkout the app's Gemfile points at
COPY --from=generate /red /red

# Install application gems
COPY --from=generate /rails/vendor/ ./vendor/
COPY --from=generate /rails/Gemfile /rails/Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY --from=generate /rails ./

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application, and the RED checkout it points at
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails
COPY --from=build /red /red

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
