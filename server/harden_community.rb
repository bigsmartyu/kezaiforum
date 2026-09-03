# frozen_string_literal: true

# Run inside the Discourse container with RAILS_ENV=production.

settings = {
  title: "科仔交流社区",
  site_description: "科仔交流社区内部实名讨论与公开聊天空间。请遵守法律法规，真实、友善、负责地交流。",
  short_site_description: "内部实名、友善、守法的交流社区",
  login_required: true,
  enable_local_logins: true,
  enable_local_logins_via_email: false,
  invite_only: true,
  enable_signup_cta: false,
  full_name_requirement: "required_at_signup",
  hide_user_profiles_from_public: true,
  persistent_sessions: true,
  maximum_session_age: 8760,
  min_password_length: 8,
  min_admin_password_length: 20,
  password_unique_characters: 6,
  approve_post_count: 2,
  max_new_accounts_per_registration_ip: 3,
  max_logins_per_ip_per_minute: 5,
  max_logins_per_ip_per_hour: 20,
  newuser_max_links: 2,
  newuser_max_embedded_media: 2,
  newuser_max_mentions_per_post: 3,
  content_security_policy_script_src: "'sha256-nZVj6O3Tn6V/fjINYhk4QdKP3NewwNhCav5STlK9yxw='|'sha256-f0HcmMfQKWPJf9aSX/1ayjpG/jeiRFww6vda4K6mCrA='",
}

settings.each { |name, value| SiteSetting.public_send("#{name}=", value) }

logo_path = "/var/www/discourse/plugins/innox-lan/assets/app-icon-512.png"
if File.file?(logo_path)
  system_user = User.find_by(id: -1)
  logo_upload = Upload.find_by(user_id: system_user.id, original_filename: "kezai-community-icon.png")
  unless logo_upload&.persisted?
    logo_upload = UploadCreator.new(File.open(logo_path), "kezai-community-icon.png").create_for(system_user.id)
  end
  if logo_upload&.persisted?
    %w[logo logo_small mobile_logo favicon large_icon].each do |name|
      SiteSetting.public_send("#{name}=", logo_upload) if SiteSetting.respond_to?("#{name}=")
    end
  end
end

blocked_phrases = [
  "代开增值税发票",
  "代办假证",
  "出售银行卡",
  "收购银行卡",
  "刷单返利",
  "解冻保证金",
  "杀猪盘",
  "洗钱通道",
  "网络赌博平台",
  "出售毒品",
  "毒品交易",
  "买卖枪支",
  "制作炸弹教程",
  "杀人教程",
  "自杀教程",
  "儿童色情",
  "色情服务",
  "传播淫秽视频",
  "人肉开盒",
  "身份证开盒",
  "诈骗教程",
]

review_phrases = [
  "非法集资",
  "暴力威胁",
  "泄露个人隐私",
  "人肉搜索",
  "网络传销",
  "违禁品交易",
]

managed_phrases = blocked_phrases + review_phrases
WatchedWord.where(word: managed_phrases).delete_all
blocked_phrases.each { |word| WatchedWord.create!(word: word, action: WatchedWord.actions[:block]) }
review_phrases.each do |word|
  WatchedWord.create!(word: word, action: WatchedWord.actions[:require_approval])
end

admin = User.find_by(username: "admin", admin: true)
if admin
  admin.update!(name: "科仔社区管理员")
  {
    "kezai_member_id" => "KZ-A-#{admin.id.to_s.rjust(6, '0')}",
    "kezai_member_category" => "管理员",
    "kezai_real_name" => "科仔社区管理员",
    "kezai_office" => "社区管理办公室",
    "kezai_real_name_status" => "管理员账号",
  }.each do |name, value|
    field = UserCustomField.find_or_initialize_by(user_id: admin.id, name: name)
    field.value = value
    field.save!
  end
  admin.user_profile.update!(location: "社区管理办公室")
end

rules_title = "科仔交流社区守则｜请先阅读"
unless Topic.find_by(title: rules_title)
  author = admin || Discourse.system_user
  rules_category = Category.find_by(name: "常规") || Category.find_by(id: 1)
  raw = <<~MD
    欢迎来到科仔交流社区。这里实行内部实名登记，请使用本人真实姓名和实际办公地点注册，并妥善保管账号和密码。

    请遵守法律法规，尊重他人，不发布违法、有害、欺诈、色情、暴力、侵害隐私、侮辱诽谤或骚扰信息；不要冒用他人身份，不要泄露他人的姓名、电话、证件、住址、工作安排等信息。

    系统会自动拦截部分高风险内容，新成员最初发布的内容可能进入管理审核。违规内容可被删除，账号可被暂停；涉嫌违法的情况将按实际需要留存记录并交由有权人员处理。

    内部实名登记由成员本人承诺信息真实，不等同于证件或公安身份核验。对身份有疑问时，请联系社区管理员进行线下核对。
  MD
  post = PostCreator.create!(author, title: rules_title, raw: raw, category: rules_category.id)
  post.topic.update!(pinned_at: Time.zone.now, pinned_globally: true, pinned_until: nil)
end

puts "HARDENING_OK"
puts "TITLE=#{SiteSetting.title}"
puts "LOGIN_REQUIRED=#{SiteSetting.login_required}"
puts "PASSWORD_MIN=#{SiteSetting.min_password_length}"
puts "FIRST_POSTS_REVIEWED=#{SiteSetting.approve_post_count}"
puts "BLOCKED_WORDS=#{WatchedWord.where(word: blocked_phrases, action: WatchedWord.actions[:block]).count}"
puts "REVIEW_WORDS=#{WatchedWord.where(word: review_phrases, action: WatchedWord.actions[:require_approval]).count}"
