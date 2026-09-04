# frozen_string_literal: true

# Run inside the Discourse container with RAILS_ENV=production.

bot_username = "kezai_ai"
bot = User.find_by(username_lower: bot_username)
bot ||= User.find_by(id: -3)

unless bot
  bot =
    User.create!(
      id: -3,
      username: bot_username,
      name: "科仔 AI 助手",
      email: "kezai-ai@invalid.local",
      password: SecureRandom.hex(32),
      active: true,
      approved: true,
      admin: false,
      moderator: false,
      trust_level: TrustLevel[4],
      skip_email_validation: true,
    )
end

raise "BOT_ID_MUST_BE_NEGATIVE" unless bot.bot?

bot.update!(
  username: bot_username,
  name: "科仔 AI 助手",
  title: "本地 AI 助手",
  active: true,
  approved: true,
  admin: false,
  moderator: false,
)
bot.user_option.update!(chat_enabled: true, allow_private_messages: false)

settings = {
  innox_ai_chat_enabled: true,
  innox_ai_chat_url: "http://172.17.0.1:11435/api/chat",
  innox_ai_chat_model: "qwen3:0.6b",
  innox_ai_chat_bot_username: bot_username,
  innox_ai_chat_timeout_seconds: 20,
}
settings.each { |name, value| SiteSetting.public_send("#{name}=", value) }

puts "AI_CHAT_OK"
puts "BOT=#{bot.id}:#{bot.username}:#{bot.name}:bot=#{bot.bot?}"
puts "CHAT_MODEL=#{SiteSetting.innox_ai_chat_model}"
puts "CHAT_ENABLED=#{SiteSetting.innox_ai_chat_enabled}"
puts "TRIGGERS=@kezai_ai|科仔AI|科仔助手"
