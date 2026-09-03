# frozen_string_literal: true

# Run inside the Discourse container with RAILS_ENV=production.

def verify!(condition, message)
  raise "VERIFY_FAILED: #{message}" unless condition
end

category = Category.find_by(slug: "anonymous-community")
verify!(category.present?, "anonymous category is missing")
verify!(SiteSetting.allow_anonymous_mode, "anonymous mode is disabled")
verify!(SiteSetting.innox_anonymous_category_id.to_i == category.id, "anonymous category is not bound")
verify!(SiteSetting.anonymous_posting_allowed_groups_map.include?(5), "registered members cannot switch identity")
verify!(SiteSetting.personal_message_enabled_groups_map.include?(5), "forum private messages are unavailable")
verify!(SiteSetting.direct_message_enabled_groups_map.include?(5), "chat direct messages are unavailable")

required_profile_fields = %w[kezai_member_id kezai_member_category kezai_real_name kezai_office]
visible_profile_fields = SiteSetting.public_user_custom_fields.to_s.split("|")
verify!((required_profile_fields - visible_profile_fields).empty?, "member profile fields are not visible")

ActiveRecord::Base.transaction do
  suffix = SecureRandom.hex(4)
  password = "KezaiTest#{SecureRandom.hex(8)}9"
  alice =
    User.create!(
      username: "qa_alice_#{suffix}",
      name: "匿名功能测试甲",
      email: "qa-alice-#{suffix}@kezai.invalid",
      password: password,
      active: true,
      approved: true,
      trust_level: 1,
      manual_locked_trust_level: 1,
      skip_email_validation: true,
    )
  bob =
    User.create!(
      username: "qa_bob_#{suffix}",
      name: "匿名功能测试乙",
      email: "qa-bob-#{suffix}@kezai.invalid",
      password: password,
      active: true,
      approved: true,
      trust_level: 1,
      manual_locked_trust_level: 1,
      skip_email_validation: true,
    )
  alice.activate
  bob.activate
  alice.user_profile.update!(location: "测试办公室A101")
  bob.user_profile.update!(location: "测试办公室B202")

  verify!(Guardian.new(alice).can_send_private_message?(bob), "forum private message policy rejected a member")
  verify!(Guardian.new(alice).can_create_direct_message?, "chat direct-message policy rejected a member")

  direct_message_context =
    Chat::CreateDirectMessageChannel.call(
      guardian: Guardian.new(alice),
      params: { target_usernames: [bob.username] },
    )
  verify!(direct_message_context.success?, "direct chat could not be created")

  shadow = AnonymousShadowCreator.get(alice)
  verify!(shadow&.anonymous?, "anonymous identity was not created")
  verify!(shadow.master_user&.id == alice.id, "administrator traceability is missing")

  clean_result =
    NewPostManager.new(
      shadow,
      title: "匿名审核流程验证 #{suffix}",
      raw: "这是一条用于验证匿名发布审核流程的普通测试内容。",
      category: category.id,
    ).perform
  verify!(clean_result.success?, "anonymous post could not enter review")
  verify!(clean_result.action == :enqueued, "anonymous post bypassed the review queue")
  verify!(clean_result.reviewable&.pending?, "anonymous review item is not pending")
  verify!(clean_result.reviewable.payload.dig("innox_ai_moderation", "anonymous") == true, "anonymous review marker is missing")
  verify!(clean_result.reviewable.target_created_by.master_user.id == alice.id, "review item cannot be traced to the member")

  outside_result =
    NewPostManager.new(
      shadow,
      title: "匿名越区验证 #{suffix}",
      raw: "这条内容不应被允许发布到匿名社区以外。",
      category: 4,
    ).perform
  verify!(outside_result.failed?, "anonymous identity posted outside the anonymous category")
  verify!(outside_result.errors.full_messages.join.include?("匿名身份只能"), "outside-category error is unclear")

  puts "ANONYMOUS_FLOW=PASS"
  puts "ANONYMOUS_REVIEW=PASS"
  puts "ADMIN_TRACEABILITY=PASS"
  puts "OUTSIDE_CATEGORY_BLOCK=PASS"
  puts "FORUM_PRIVATE_MESSAGE=PASS"
  puts "CHAT_DIRECT_MESSAGE=PASS"
  puts "PROFILE_VISIBILITY_SETTINGS=PASS"

  raise ActiveRecord::Rollback
end

puts "ROLLBACK_CLEANUP=PASS"
