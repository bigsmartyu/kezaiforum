# frozen_string_literal: true

module ::InnoxLan
  module InvitesControllerExtension
    def show
      invite = innox_invite_from_params
      if invite&.redeemable?
        return redirect_to("#{Discourse.base_path('/join')}?invite=#{ERB::Util.url_encode(invite.invite_key)}")
      end

      super
    end

    private

    def ensure_new_registrations_allowed
      return if innox_invite_from_params&.redeemable?

      super
    end

    def innox_invite_from_params
      key = params[:id].to_s.strip
      return if key.blank?

      Invite.find_by(invite_key: key)
    end
  end
end
