# frozen_string_literal: true

# name: innox-lan
# about: Secure LAN registration and identity mapping for 科仔交流社区
# version: 1.3.0
# authors: 科仔交流社区
# url: https://kezaiforum.xyz
# required_version: 3.2.0

enabled_site_setting :innox_lan_enabled

module ::InnoxLan
  PLUGIN_NAME = "innox-lan"
end

require_relative "lib/innox_lan/engine"

after_initialize do
  require_relative "lib/innox_lan/invites_controller_extension"
  ::InvitesController.prepend(::InnoxLan::InvitesControllerExtension)

  ::ApplicationController.class_eval do
    before_action :innox_lan_enforce_public_https

    private

    def innox_lan_enforce_public_https
      return unless SiteSetting.innox_lan_enabled
      return if request.ssl?
      return unless request.headers["HTTP_CF_VISITOR"].to_s.include?('"scheme":"http"')

      redirect_to "https://kezaiforum.xyz#{request.fullpath}", status: :moved_permanently, allow_other_host: true
    end
  end

  Discourse::Application.routes.prepend do
    get "/" => "innox_lan/registrations#new"
    get "/login" => "innox_lan/registrations#new"
    get "/signup" => "innox_lan/registrations#new", defaults: { mode: "register" }
  end
end
