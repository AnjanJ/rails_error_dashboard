# frozen_string_literal: true

module RailsErrorDashboard
  module UserAgentHelper
    # These helpers translate, so they depend on red_t explicitly rather
    # than on the controller happening to mix every engine helper into
    # one view context.
    include I18nHelper

    # Parse user agent string into browser, OS, and device info
    def parse_user_agent(user_agent_string)
      return default_user_agent_info if user_agent_string.blank?

      browser = Browser.new(user_agent_string)

      {
        browser_name: browser_name(browser),
        browser_version: browser.version,
        os_name: os_name(browser),
        device_type: device_type(browser),
        # No titleize: the platform is a machine identifier from the browser
        # gem, and titleize applies English morphology to it. Nothing renders
        # this value today; it stays raw so a future reader gets the identifier
        # rather than a mangled version of one.
        platform: browser.platform.to_s,
        is_mobile: browser.device.mobile?,
        is_tablet: browser.device.tablet?,
        is_bot: browser.bot?
      }
    rescue StandardError => e
      Rails.logger.warn "[RailsErrorDashboard] Failed to parse user agent: #{e.message}"
      default_user_agent_info
    end

    # Get browser icon based on browser name
    def browser_icon(browser_info)
      return '<i class="bi bi-question-circle text-muted"></i>'.html_safe if browser_info.blank?

      case browser_info[:browser_name]&.downcase
      when "chrome"
        '<i class="bi bi-browser-chrome text-warning"></i>'.html_safe
      when "firefox"
        '<i class="bi bi-browser-firefox text-danger"></i>'.html_safe
      when "safari"
        '<i class="bi bi-browser-safari text-primary"></i>'.html_safe
      when "edge"
        '<i class="bi bi-browser-edge text-info"></i>'.html_safe
      else
        '<i class="bi bi-globe text-secondary"></i>'.html_safe
      end
    end

    # Get OS icon based on OS name
    def os_icon(browser_info)
      return '<i class="bi bi-question-circle text-muted"></i>'.html_safe if browser_info.blank?

      case browser_info[:os_name]&.downcase
      when /windows/
        '<i class="bi bi-windows text-primary"></i>'.html_safe
      when /mac|darwin/
        '<i class="bi bi-apple text-secondary"></i>'.html_safe
      when /linux/
        '<i class="bi bi-ubuntu text-danger"></i>'.html_safe
      when /android/
        '<i class="bi bi-android2 text-success"></i>'.html_safe
      when /ios|iphone|ipad/
        '<i class="bi bi-apple text-secondary"></i>'.html_safe
      else
        '<i class="bi bi-cpu text-muted"></i>'.html_safe
      end
    end

    # Get device icon based on device type
    def device_icon(browser_info)
      return '<i class="bi bi-question-circle text-muted"></i>'.html_safe if browser_info.blank?

      if browser_info[:is_mobile]
        '<i class="bi bi-phone text-success"></i>'.html_safe
      elsif browser_info[:is_tablet]
        '<i class="bi bi-tablet text-info"></i>'.html_safe
      else
        '<i class="bi bi-laptop text-secondary"></i>'.html_safe
      end
    end

    private

    # Browser and OS names are brands and stay as written in every locale.
    # Only the "Unknown" fallback is a word rather than a name.
    def browser_name(browser)
      return "Chrome" if browser.chrome?
      return "Firefox" if browser.firefox?
      return "Safari" if browser.safari?
      return "Edge" if browser.edge?
      return "Opera" if browser.opera?
      return "Internet Explorer" if browser.ie?
      red_t("red.common.unknown")
    end

    def os_name(browser)
      return "Windows" if browser.platform.windows?
      return "macOS" if browser.platform.mac?
      return "Linux" if browser.platform.linux?
      return "Android" if browser.platform.android?
      return "iOS" if browser.platform.ios?
      red_t("red.common.unknown")
    end

    # Unlike the browser and OS, these four are ordinary words, not brands.
    def device_type(browser)
      return red_t("red.common.device_type.mobile") if browser.device.mobile?
      return red_t("red.common.device_type.tablet") if browser.device.tablet?
      return red_t("red.common.device_type.bot") if browser.bot?
      red_t("red.common.device_type.desktop")
    end

    def default_user_agent_info
      unknown = red_t("red.common.unknown")

      {
        browser_name: unknown,
        browser_version: nil,
        os_name: unknown,
        device_type: unknown,
        platform: unknown,
        is_mobile: false,
        is_tablet: false,
        is_bot: false
      }
    end
  end
end
