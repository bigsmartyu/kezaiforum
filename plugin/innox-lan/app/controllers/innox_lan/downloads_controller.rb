# frozen_string_literal: true

module ::InnoxLan
  class DownloadsController < ::ApplicationController
    requires_plugin InnoxLan::PLUGIN_NAME

    skip_before_action :redirect_to_login_if_required
    skip_before_action :redirect_to_profile_if_required
    skip_before_action :check_xhr

    APK_PATH = "/shared/innox-app/Kezai-Community-v1.3.apk"

    def android
      return head :not_found unless File.file?(APK_PATH)

      send_file(
        APK_PATH,
        type: "application/vnd.android.package-archive",
        disposition: "attachment",
        filename: "Kezai-Community-v1.3.apk",
      )
    end
  end
end
