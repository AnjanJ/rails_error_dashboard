---
layout: default
title: "Uninstalling Rails Error Dashboard"
permalink: /docs/UNINSTALL
---

# Uninstalling Rails Error Dashboard

Removing RED has two parts: its data (RED's tables, and with a separate database, the database
itself) and its code (the initializer, the route, the migrations, the schema and the gem).

**Drop the data first, while the gem is still installed.** The tools that drop it ship inside the
gem. If you've already removed the gem, see [Already removed the gem?](#already-removed-the-gem).

## The uninstaller (recommended)

```bash
bin/rails generate rails_error_dashboard:uninstall
```

It lists what it found, asks you to confirm, and then:

1. drops every RED table, in foreign-key order, on the database RED uses: your app's database, or
   the separate one. First it asks you to type `DELETE ALL DATA`. If you type anything else, it
   keeps the tables and removes only the files;
2. removes `config/initializers/rails_error_dashboard.rb`;
3. removes the `mount RailsErrorDashboard::Engine` line from `config/routes.rb`;
4. deletes RED's migrations from `db/migrate/` and `db/error_dashboard_migrate/`.

If it can't drop the tables, it stops before removing any file, so the app still boots and you can
try again. If it can't reach the error database at all, it stops before doing anything (see
[Troubleshooting](#cant-reach-the-error-database-so-nothing-was-removed)).

Then finish by hand:

1. Regenerate the schema file, or `db:schema:load` and `db:prepare` will recreate RED's tables:

   ```bash
   bin/rails db:schema:dump
   ```

2. Remove `gem "rails_error_dashboard"` from the `Gemfile` and run `bundle install`.
3. With a separate database, finish with [Separate and shared databases](#separate-and-shared-databases).
4. Restart the app.

### Options

```bash
# Keep the tables and their data; remove only the files
bin/rails generate rails_error_dashboard:uninstall --keep-data

# Skip the yes/no question. Dropping the tables still asks you to type DELETE ALL DATA.
bin/rails generate rails_error_dashboard:uninstall --skip-confirmation

# Print the manual steps and change nothing
bin/rails generate rails_error_dashboard:uninstall --manual-only
```

## Step by step

To do each step yourself, keep this order:

1. Drop the tables:

   ```bash
   bin/rails rails_error_dashboard:db:drop
   ```

   It lists each table with its row count, warns you if the database holds errors from more than
   one app, and asks you to type `DELETE ALL DATA`. Like the uninstaller, it drops every RED table
   in foreign-key order, on the error database if you use one.
2. Delete `config/initializers/rails_error_dashboard.rb`.
3. Remove the `mount RailsErrorDashboard::Engine => ...` line from `config/routes.rb`.
4. Delete RED's migrations:

   ```bash
   rm db/migrate/*rails_error_dashboard*.rb
   rm db/error_dashboard_migrate/*rails_error_dashboard*.rb   # separate database only
   ```

5. Run `bin/rails db:schema:dump`.
6. Remove the gem from the `Gemfile` and run `bundle install`.
7. With a separate database, finish with [Separate and shared databases](#separate-and-shared-databases).
8. Restart the app.

## Separate and shared databases

**A separate database** (installer option 2). The uninstaller and the rake task drop RED's tables
in the error database. That leaves the database itself, its entry in `config/database.yml`, and
`db/error_dashboard_schema.rb`. After you remove the gem, drop the database if nothing else uses it:

```bash
bin/rails db:drop:error_dashboard
```

In production, Rails refuses to drop the database unless you also set
`DISABLE_DATABASE_ENVIRONMENT_CHECK=1`. Then remove the `error_dashboard:` entry from every
environment in `config/database.yml`, and delete `db/error_dashboard_schema.rb` and the empty
`db/error_dashboard_migrate/` folder.

**A shared database** (installer option 3). Several apps write to the same tables, so dropping them
deletes every app's errors. The rake task warns you when it finds more than one app. To remove RED
from one app while the others keep using it, run the uninstaller with `--keep-data`: it removes
only this app's files. Drop the tables when you remove RED from the last app.

## In production

The commands above change files on your machine and data in one database. For a deployed app:

1. **Drop the data in each environment first**, while the deployed app still has the gem. Run
   `bin/rails rails_error_dashboard:db:drop` from a shell in that environment. It asks you to type
   `DELETE ALL DATA`, so run it where you can answer. With a separate database you can instead drop the whole database afterwards, as
   above.
2. **Ship the code changes in one deploy**: the initializer, the route, the migrations, the schema
   file, `Gemfile` and `Gemfile.lock`. That way no release runs the gem without its configuration.

If you deploy the removal without step 1, the tables stay behind. Drop them as in
[Already removed the gem?](#already-removed-the-gem).

## Keep capturing errors, remove the dashboard

Comment out the `mount RailsErrorDashboard::Engine` line in `config/routes.rb`:

```ruby
# mount RailsErrorDashboard::Engine => "/red"
```

RED inserts its middleware and error subscriber itself, so errors are still captured and
notifications still go out; only the dashboard pages are gone. Comment the line out rather than
deleting it: the installer adds a `/red` mount whenever `config/routes.rb` doesn't mention the
engine, so after a deleted line the next upgrade would put the dashboard back. Leave
`config.enable_middleware` and `config.enable_error_subscriber` on: turning them off stops
capture.

## Keep the data, remove the code

`bin/rails generate rails_error_dashboard:uninstall --keep-data` removes the files and keeps the
tables. To see the data again later, add the gem back and run:

```bash
bin/rails generate rails_error_dashboard:install
bin/rails db:migrate
```

The migrations the installer copies find the existing tables and skip them, so your errors are
still there.

## Already removed the gem?

If you removed the gem before dropping the data, RED's tables are still in the database, and the
rake task went with the gem.

1. Make sure `config/initializers/rails_error_dashboard.rb` and the mount line in
   `config/routes.rb` are gone. The app can't boot while they refer to RED.
2. **Same database:** drop the tables from `bin/rails console`. This finds every table named
   `rails_error_dashboard_*` and drops each one after the tables that reference it:

   ```ruby
   connection = ActiveRecord::Base.connection
   tables = connection.tables.grep(/\Arails_error_dashboard_/)
   until tables.empty?
     # A table can go once no other remaining RED table has a foreign key to it.
     droppable = tables.reject do |table|
       (tables - [table]).any? { |other| connection.foreign_keys(other).any? { |fk| fk.to_table == table } }
     end
     raise "foreign-key cycle among #{tables.join(', ')}" if droppable.empty?
     droppable.each { |table| connection.drop_table(table) }
     tables -= droppable
   end
   ```

   **Separate database:** run `bin/rails db:drop:error_dashboard` (with
   `DISABLE_DATABASE_ENVIRONMENT_CHECK=1` in production), then remove its entry from
   `config/database.yml`.
3. Delete RED's migrations and run `bin/rails db:schema:dump`, as in [Step by step](#step-by-step).

## Check that it's gone

```bash
# Both print nothing
bin/rails runner 'puts ActiveRecord::Base.connection.tables.grep(/\Arails_error_dashboard_/)'
grep -rn "rails_error_dashboard\|RailsErrorDashboard" Gemfile config db/schema.rb
```

## Troubleshooting

### "Can't reach the error database, so nothing was removed"

The uninstaller couldn't connect to the separate error database: `config/database.yml` has no
`error_dashboard` entry for this environment, or the database server is down. It stops before
removing anything, because without the initializer nothing would know where the tables are. Fix
the entry (or start the server) and run it again, or pass `--keep-data` to remove only the files.
The rake task also refuses, with its own message, before dropping anything.

### "Not dropping anything: these tables have foreign keys into RED's tables"

One of your app's own tables has a foreign key to a RED table, so RED drops nothing. The message
names each foreign key. Remove them, then run the uninstaller again.

### RED's tables come back

`db:schema:load` and `db:prepare` build the database from your schema file. Run
`bin/rails db:schema:dump` after RED's tables are gone, and commit the result. With a separate
database, also delete `db/error_dashboard_schema.rb`.

### `NO FILE` rows in `db:migrate:status`

The versions of RED's migrations stay in `schema_migrations` after you delete their files, so
`db:migrate:status` lists them as `NO FILE`. They're harmless: there's nothing left to run.

## Environment Variables

After uninstalling you can remove these, wherever you set them:

```bash
ERROR_DASHBOARD_USER
ERROR_DASHBOARD_PASSWORD
SLACK_WEBHOOK_URL
ERROR_NOTIFICATION_EMAILS
DISCORD_WEBHOOK_URL
PAGERDUTY_INTEGRATION_KEY
WEBHOOK_URLS
DASHBOARD_BASE_URL
USE_SEPARATE_ERROR_DB
```

## Reinstalling Later

```bash
# Gemfile
gem 'rails_error_dashboard'

bundle install
bin/rails generate rails_error_dashboard:install
bin/rails db:migrate
```

If you kept the data, it's still there.

---

## Need Help?

If you encounter issues during uninstall:

- **Issues**: [GitHub Issues](https://github.com/AnjanJ/rails_error_dashboard/issues)
- **Discussions**: [GitHub Discussions](https://github.com/AnjanJ/rails_error_dashboard/discussions)

---

## Feedback

We're sorry to see you go! If you have a moment, we'd love to know why you're uninstalling:

- **GitHub Discussions**: Share your feedback (optional but appreciated)
- **GitHub Issues**: Report bugs or missing features that led to uninstall

Your feedback helps us improve Rails Error Dashboard for everyone. Thank you! 🙏
