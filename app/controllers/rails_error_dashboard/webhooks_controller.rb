# frozen_string_literal: true

module RailsErrorDashboard
  # Receives webhooks from GitHub/GitLab/Codeberg/Linear for two-way issue sync.
  #
  # When an issue is closed/reopened on the platform, the corresponding
  # error in the dashboard is resolved/reopened to match.
  #
  # Security: HMAC signature verification for each provider.
  # - GitHub:   X-Hub-Signature-256 (HMAC-SHA256)
  # - GitLab:   X-Gitlab-Token (shared secret)
  # - Codeberg: X-Gitea-Signature (HMAC-SHA256)
  # - Linear:   Linear-Signature (HMAC-SHA256)
  class WebhooksController < ActionController::Base
    skip_before_action :verify_authenticity_token

    before_action :verify_webhook_enabled
    before_action :verify_signature

    def receive
      provider = params[:provider]
      payload = parse_payload

      return head :ok unless payload

      case provider
      when "github"
        handle_github(payload)
      when "gitlab"
        handle_gitlab(payload)
      when "codeberg"
        handle_codeberg(payload)
      when "linear"
        handle_linear(payload)
      else
        head :not_found
        return
      end

      head :ok
    rescue => e
      Rails.logger.error("[RailsErrorDashboard] Webhook error: #{e.class}: #{e.message}")
      head :ok # Always return 200 to prevent webhook retries on our errors
    end

    private

    def verify_webhook_enabled
      config = RailsErrorDashboard.configuration
      unless config.enable_issue_tracking && config.issue_webhook_secret.present?
        head :not_found
      end
    end

    def verify_signature
      provider = params[:provider]
      secret = RailsErrorDashboard.configuration.issue_webhook_secret

      unless secret.present?
        Rails.logger.warn("[RailsErrorDashboard] Webhook received but no issue_webhook_secret configured")
        head :unauthorized
        return
      end

      body = request.body.read
      request.body.rewind

      verified = case provider
      when "github"
        verify_github_signature(body, secret)
      when "gitlab"
        verify_gitlab_token(secret)
      when "codeberg"
        verify_codeberg_signature(body, secret)
      when "linear"
        verify_linear_signature(body, secret)
      else
        false
      end

      head :unauthorized unless verified
    end

    def verify_github_signature(body, secret)
      signature = request.headers["X-Hub-Signature-256"]
      return false unless signature

      expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, body)
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end

    def verify_gitlab_token(secret)
      token = request.headers["X-Gitlab-Token"]
      return false unless token

      ActiveSupport::SecurityUtils.secure_compare(secret, token)
    end

    def verify_codeberg_signature(body, secret)
      signature = request.headers["X-Gitea-Signature"]
      return false unless signature

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, body)
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end

    def verify_linear_signature(body, secret)
      signature = request.headers["Linear-Signature"]
      return false unless signature

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, body)
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end

    def parse_payload
      JSON.parse(request.body.read)
    rescue JSON::ParserError
      nil
    ensure
      request.body.rewind
    end

    # GitHub: issues webhook fires with action: opened/closed/reopened
    def handle_github(payload)
      return unless payload["action"].in?(%w[closed reopened])

      issue_number = payload.dig("issue", "number")
      return unless issue_number

      error = find_error_by_issue(issue_number, "github")
      return unless error

      case payload["action"]
      when "closed"
        resolve_error(error, "Closed on GitHub by #{payload.dig("sender", "login")}")
      when "reopened"
        reopen_error(error)
      end
    end

    # GitLab: issue webhook fires with object_attributes.action
    def handle_gitlab(payload)
      action = payload.dig("object_attributes", "action")
      return unless action.in?(%w[close reopen])

      issue_iid = payload.dig("object_attributes", "iid")
      return unless issue_iid

      error = find_error_by_issue(issue_iid, "gitlab")
      return unless error

      case action
      when "close"
        resolve_error(error, "Closed on GitLab by #{payload.dig("user", "username")}")
      when "reopen"
        reopen_error(error)
      end
    end

    # Codeberg/Gitea/Forgejo: issue webhook fires with action
    def handle_codeberg(payload)
      return unless payload["action"].in?(%w[closed reopened])

      issue_number = payload.dig("issue", "number")
      return unless issue_number

      error = find_error_by_issue(issue_number, "codeberg")
      return unless error

      case payload["action"]
      when "closed"
        resolve_error(error, "Closed on Codeberg by #{payload.dig("sender", "login")}")
      when "reopened"
        reopen_error(error)
      end
    end

    # Linear: Issue webhook fires with action create/update/remove. State changes
    # arrive as updates with the old stateId in updatedFrom. Linear has no
    # open/closed binary — completed/canceled state types map to resolved.
    def handle_linear(payload)
      return unless payload["type"] == "Issue" && payload["action"] == "update"
      return unless payload["updatedFrom"]&.key?("stateId")

      issue_number = payload.dig("data", "number")
      return unless issue_number

      error = find_error_by_issue(issue_number, "linear")
      return unless error

      state_type = payload.dig("data", "state", "type")
      if state_type.in?(%w[completed canceled])
        resolve_error(error, "Completed on Linear by #{payload.dig("actor", "name")}")
      elsif state_type.in?(%w[triage backlog unstarted started])
        reopen_error(error)
      end
    end

    def find_error_by_issue(issue_number, provider)
      ErrorLog.find_by(
        external_issue_number: issue_number,
        external_issue_provider: provider
      )
    end

    def resolve_error(error, message)
      return if error.resolved?

      Commands::ResolveError.call(
        error.id,
        resolved_by_name: "Webhook",
        resolution_comment: message
      )
    end

    def reopen_error(error)
      return unless error.resolved?

      error.update!(
        resolved: false,
        resolved_at: nil,
        status: "new",
        reopened_at: Time.current
      )
    end
  end
end
