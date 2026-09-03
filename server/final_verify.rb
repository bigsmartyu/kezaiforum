# frozen_string_literal: true

admin = User.find_by!(username: "admin", admin: true)
rules = Topic.find_by(title: "科仔交流社区守则｜请先阅读")

checks = {
  title: SiteSetting.title == "科仔交流社区",
  login_required: SiteSetting.login_required,
  invite_only: SiteSetting.invite_only,
  signup_cta_disabled: !SiteSetting.enable_signup_cta,
  full_name_required: SiteSetting.full_name_requirement == "required_at_signup",
  profiles_private: SiteSetting.hide_user_profiles_from_public,
  password_minimum: SiteSetting.min_password_length >= 8,
  admin_password_minimum: SiteSetting.min_admin_password_length >= 20,
  persistent_sessions: SiteSetting.persistent_sessions && SiteSetting.maximum_session_age >= 8760,
  first_posts_reviewed: SiteSetting.approve_post_count == 2,
  ordinary_users_empty: User.where("id > 0").where(admin: false).none?,
  one_admin_only: User.where("id > 0", admin: true).count == 1,
  pending_reviews_empty: Reviewable.where(status: Reviewable.statuses[:pending]).none?,
  admin_sessions_empty: admin.user_auth_tokens.none?,
  rules_pinned: rules&.pinned_globally == true,
  blocked_words: WatchedWord.where(action: WatchedWord.actions[:block]).count >= 21,
  reviewed_words: WatchedWord.where(action: WatchedWord.actions[:require_approval]).count >= 6,
  admin_member_id: UserCustomField.exists?(user_id: admin.id, name: "kezai_member_id", value: "KZ-A-000001"),
}

checks.each { |name, value| puts "#{name}=#{value}" }
puts "positive_users=#{User.where('id > 0').count}"
puts "ordinary_users=#{User.where('id > 0').where(admin: false).count}"
puts "admin=#{admin.id}|#{admin.username}|#{admin.name}"
puts checks.values.all? ? "FINAL_VERIFY_OK" : "FINAL_VERIFY_FAILED"

exit(1) unless checks.values.all?
