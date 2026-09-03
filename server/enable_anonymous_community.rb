# frozen_string_literal: true

# Run inside the Discourse container with RAILS_ENV=production.

category = Category.find_by(slug: "anonymous-community")
category ||=
  Category.new(
    name: "匿名社区",
    slug: "anonymous-community",
    user: Discourse.system_user,
    color: "5B6FD8",
    text_color: "FFFFFF",
  )

category.name = "匿名社区"
category.description =
  PrettyText.cook(
    "在这里可以选择匿名身份发帖或回复。所有匿名内容都会先经过自动检查，再由管理员批准后公开。匿名只对普通成员隐藏；为维护社区安全，管理员仍可追溯实名账号。禁止违法、辱骂、骚扰或泄露隐私。",
  )
category.set_permissions(everyone: :full)
category.save!
category.reload
category.topic&.update!(title: "关于匿名社区")

settings = {
  allow_anonymous_mode: true,
  anonymous_posting_allowed_groups: "1|2|5",
  anonymous_account_duration_minutes: 10_080,
  enable_user_directory: true,
  hide_user_profiles_from_public: true,
  hide_new_user_profiles: false,
  personal_message_enabled_groups: "1|2|5",
  chat_allowed_groups: "1|2|5",
  direct_message_enabled_groups: "1|2|5",
  chat_message_flag_allowed_groups: "1|2|5",
  innox_anonymous_category_id: category.id,
}

settings.each { |name, value| SiteSetting.public_send("#{name}=", value) }

profile_fields = %w[
  kezai_member_id
  kezai_member_category
  kezai_real_name
  kezai_office
  kezai_real_name_status
]
existing_profile_fields = SiteSetting.public_user_custom_fields.to_s.split("|").reject(&:blank?)
SiteSetting.public_user_custom_fields = (existing_profile_fields + profile_fields).uniq.join("|")

guide_title = "匿名社区使用说明｜发帖前请阅读"
unless Topic.find_by(title: guide_title)
  admin = User.find_by(username: "admin", admin: true) || Discourse.system_user
  raw = <<~MD
    这里支持实名发布和匿名发布。需要匿名时，请打开右上角头像菜单，选择“进入匿名模式”，再回到本分类发帖或回复；完成后可在同一位置切回实名身份。

    所有匿名内容都会先经过本机审核模型检查，并进入管理员待审列表；管理员批准后才会公开。普通成员看不到匿名作者的实名资料，但管理员为了审核、安全和处理投诉，可以查到对应的实名账号。

    匿名不等于不负责。请勿发布违法、辱骂、骚扰、人身攻击、广告引流或泄露他人隐私的内容。匿名身份不能用于私聊；如需与其他成员沟通，请切回实名身份后打开对方资料页发起私聊。
  MD
  post =
    PostCreator.create!(
      admin,
      title: guide_title,
      raw: raw,
      category: category.id,
      skip_validations: true,
    )
  post.topic.update!(pinned_at: Time.zone.now, pinned_globally: false, pinned_until: nil)
end

puts "ANONYMOUS_COMMUNITY_OK"
puts "CATEGORY_ID=#{category.id}"
puts "CATEGORY_SLUG=#{category.slug}"
puts "ANONYMOUS_MODE=#{SiteSetting.allow_anonymous_mode}"
puts "ANONYMOUS_GROUPS=#{SiteSetting.anonymous_posting_allowed_groups}"
puts "PRIVATE_MESSAGES=#{SiteSetting.personal_message_enabled_groups}"
puts "DIRECT_CHAT=#{SiteSetting.direct_message_enabled_groups}"
puts "PUBLIC_PROFILE_FIELDS=#{SiteSetting.public_user_custom_fields}"
