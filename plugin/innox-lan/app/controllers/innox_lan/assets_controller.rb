# frozen_string_literal: true

module ::InnoxLan
  class AssetsController < ::ApplicationController
    requires_plugin InnoxLan::PLUGIN_NAME

    skip_before_action :redirect_to_login_if_required
    skip_before_action :redirect_to_profile_if_required
    skip_before_action :check_xhr
    skip_forgery_protection only: :script

    ASSET_DIR = File.expand_path("../../../assets", __dir__)

    def logo
      send_asset("innox-logo-white.png", "image/png")
    end

    def mark
      send_asset("innox-mark-color.png", "image/png")
    end

    def founder
      send_asset("kezai-community-board-v1.png", "image/png")
    end

    def mascot_board
      send_asset("kezai-duo-v2-web.jpg", "image/jpeg")
    end

    def kezai_girl
      send_asset("kezai-girl-v2-thumb.jpg", "image/jpeg")
    end

    def kezai_astronaut
      send_asset("kezai-astronaut-v2-thumb.jpg", "image/jpeg")
    end

    def kezai_duo
      send_asset("kezai-duo-v2-web.jpg", "image/jpeg")
    end

    def script
      send_asset("join.js", "application/javascript; charset=utf-8")
    end

    def manifest
      send_asset("manifest.webmanifest", "application/manifest+json; charset=utf-8")
    end

    def app_icon_192
      send_asset("app-icon-192.png", "image/png")
    end

    def app_icon_512
      send_asset("app-icon-512.png", "image/png")
    end

    private

    def send_asset(filename, content_type)
      path = File.join(ASSET_DIR, filename)
      return head :not_found unless File.file?(path)

      expires_in 7.days, public: true
      send_file(path, type: content_type, disposition: "inline")
    end
  end
end
