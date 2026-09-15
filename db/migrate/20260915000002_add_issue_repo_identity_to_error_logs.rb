# frozen_string_literal: true

# Record WHICH repository (or Linear team) a linked issue belongs to.
#
# A linked issue was identified by provider + issue number alone, so issue 42
# on github.com/acme/api and issue 42 on github.com/acme/web were the same
# identity to RED. A validly signed webhook from the second repository
# resolved the error linked to the first. It matters for shared databases,
# several linked repositories, a repository rename, and Linear, where issue
# numbers are scoped per team and collide constantly.
#
# The repository identity is present in every payload RED already parses and
# in every issue URL LinkExistingIssue already matches -- it was extracted and
# then discarded. This column keeps it.
#
# Shape per provider, matching what each API client already expects as `repo`:
#   github    "owner/repo"
#   gitlab    "group/project"      (URL-encoded by the client)
#   codeberg  "owner/repo"         (Gitea/Forgejo)
#   linear    "ENG"                (team key -- Linear has no repository)
#
# Nullable: rows linked before this migration have no recorded repository.
# Those are matched leniently (provider + number, as before) so an existing
# link keeps working, and the identity is filled in the first time a webhook
# or a re-link supplies it. A backfill is not possible in general -- the URL
# is the only evidence, and it is parsed here where it exists.
class AddIssueRepoIdentityToErrorLogs < ActiveRecord::Migration[7.0]
  TABLE = :rails_error_dashboard_error_logs

  def up
    return unless table_exists?(TABLE)
    return if column_exists?(TABLE, :external_issue_repo)

    # 255: "group/subgroup/subgroup/project" on GitLab can be long, and this
    # column is matched, not indexed on its own.
    add_column TABLE, :external_issue_repo, :string, limit: 255

    # The lookup a webhook performs: provider + number + repository.
    add_index TABLE, [ :external_issue_provider, :external_issue_number, :external_issue_repo ],
              name: "index_error_logs_on_issue_identity"

    backfill_from_urls!
  end

  def down
    return unless table_exists?(TABLE)

    if index_name_exists?(TABLE, "index_error_logs_on_issue_identity")
      remove_index TABLE, name: "index_error_logs_on_issue_identity"
    end
    remove_column TABLE, :external_issue_repo if column_exists?(TABLE, :external_issue_repo)
  end

  private

  # Recover the repository from the stored issue URL where its shape makes
  # that unambiguous. Anything unrecognised stays NULL and is matched
  # leniently until a webhook or a re-link supplies the identity.
  def backfill_from_urls!
    ErrorLogRow.where.not(external_issue_url: nil)
               .where(external_issue_repo: nil)
               .find_each do |row|
      repo = parse_repo(row.external_issue_url)
      next if repo.blank?

      ErrorLogRow.where(id: row.id).update_all(external_issue_repo: repo)
    end
  rescue => e
    # A backfill must never block the migration: NULL simply means "matched
    # leniently", which is exactly the pre-migration behaviour.
    say "skipped issue repository backfill: #{e.class} - #{e.message}", true
  end

  def parse_repo(url)
    case url.to_s
    when %r{github\.com/([^/]+/[^/]+)/issues/\d+}i     then Regexp.last_match(1)
    when %r{gitlab\.com/([^/]+/[^/]+)/-/issues/\d+}i   then Regexp.last_match(1)
    when %r{codeberg\.org/([^/]+/[^/]+)/issues/\d+}i   then Regexp.last_match(1)
    when %r{linear\.app/[^/]+/issue/([A-Za-z][A-Za-z0-9]*)-\d+}i then Regexp.last_match(1).upcase
    end
  end

  # Bare class: the real model carries callbacks, a default scope and possibly
  # a separate connection. A migration reads the table as it is on disk.
  class ErrorLogRow < ActiveRecord::Base
    self.table_name = "rails_error_dashboard_error_logs"
    self.inheritance_column = nil
  end
end
