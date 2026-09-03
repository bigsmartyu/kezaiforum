# frozen_string_literal: true

# name: innox-lan
# about: Secure LAN registration and identity mapping for 科仔交流社区
# version: 1.5.0
# authors: 科仔交流社区
# url: https://kezaiforum.xyz
# required_version: 3.2.0

enabled_site_setting :innox_lan_enabled

module ::InnoxLan
  PLUGIN_NAME = "innox-lan"
end

require_relative "lib/innox_lan/engine"

after_initialize do
  require_relative "lib/innox_lan/content_moderation"
  require_relative "lib/innox_lan/invites_controller_extension"
  ::InvitesController.prepend(::InnoxLan::InvitesControllerExtension)

  NewPostManager.add_plugin_payload_attribute(:innox_ai_moderation)
  NewPostManager.add_handler(100) do |manager|
    next if manager.args[:skip_validations] || manager.args[:import_mode]

    anonymous_user = manager.user&.anonymous?
    if anonymous_user
      category_id =
        if manager.args[:topic_id].present?
          Topic.where(id: manager.args[:topic_id]).pick(:category_id)
        else
          manager.args[:category].to_i
        end
      anonymous_category_id = SiteSetting.innox_anonymous_category_id.to_i

      if anonymous_category_id <= 0 || category_id.to_i != anonymous_category_id
        blocked = NewPostResult.new(:created_post, false)
        blocked.errors.add(:base, "匿名身份只能在“匿名社区”内发帖或回复。请先切回实名身份，或进入匿名社区后再发布。")
        next blocked
      end
    end

    next unless SiteSetting.innox_ai_moderation_enabled || anonymous_user

    text = [manager.args[:title], manager.args[:raw]].compact.join("\n")
    result =
      if SiteSetting.innox_ai_moderation_enabled
        InnoxLan::ContentModeration.check_post(text, user_id: manager.user&.id)
      else
        InnoxLan::ContentModeration::Result.new(
          status: :controversial,
          categories: ["Anonymous manual review"],
          trigger_groups: [],
        )
      end

    if anonymous_user
      manager.args[:innox_ai_moderation] = result.review_payload.merge(anonymous: true)
      next manager.enqueue(
        result.error? ? :innox_anonymous_ai_unavailable : :innox_anonymous_review,
      )
    end

    next if result.safe?

    private_message =
      manager.args[:archetype] == Archetype.private_message ||
        (
          manager.args[:topic_id] &&
            Topic.where(id: manager.args[:topic_id], archetype: Archetype.private_message).exists?
        )
    if private_message
      blocked = NewPostResult.new(:created_post, false)
      blocked.errors.add(
        :base,
        result.error? ? "审核服务暂时不可用，请稍后再发送。" : "这条私信包含需要审核的内容，请调整后再发送。",
      )
      next blocked
    end

    manager.args[:innox_ai_moderation] = result.review_payload
    manager.enqueue(result.error? ? :innox_ai_unavailable : :innox_ai_review)
  end

  if defined?(::Chat::CreateMessage)
    ::Chat::CreateMessage.prepend(::InnoxLan::ChatCreateMessageModeration)
  end
  if defined?(::Chat::UpdateMessage)
    ::Chat::UpdateMessage.prepend(::InnoxLan::ChatUpdateMessageModeration)
  end

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
