# frozen_string_literal: true

# Run inside the Discourse container with RAILS_ENV=production.

def verify!(condition, message)
  raise "VERIFY_FAILED: #{message}" unless condition
end

bot = User.find_by(username_lower: SiteSetting.innox_ai_chat_bot_username.downcase)
verify!(SiteSetting.innox_ai_chat_enabled, "AI chat is disabled")
verify!(SiteSetting.innox_ai_chat_model == "qwen3:0.6b", "wrong conversational model")
verify!(bot&.bot?, "AI assistant account is missing or not marked as a bot")
verify!(InnoxLan::ChatAI.triggered?("科仔AI 你好"), "Chinese trigger is not recognized")
verify!(InnoxLan::ChatAI.triggered?("@kezai_ai hello"), "username trigger is not recognized")
verify!(!InnoxLan::ChatAI.triggered?("大家好"), "ordinary chat incorrectly triggers AI")

source_id = nil
rate_key = nil
ActiveRecord::Base.transaction do
  suffix = SecureRandom.hex(4)
  user =
    User.create!(
      username: "qa_ai_chat_#{suffix}",
      name: "AI群聊测试用户",
      email: "qa-ai-chat-#{suffix}@kezai.invalid",
      password: "KezaiTest#{SecureRandom.hex(8)}9",
      active: true,
      approved: true,
      trust_level: 1,
      skip_email_validation: true,
    )
  user.activate

  guardian = Guardian.new(user)
  channel =
    Chat::Channel.order(:id).detect do |candidate|
      !candidate.direct_message_channel? && guardian.can_post_in_chatable?(candidate.chatable)
    end
  verify!(channel.present?, "no public chat channel is available to a registered member")

  source_context =
    Chat::CreateMessage.call(
      guardian: guardian,
      params: {
        chat_channel_id: channel.id.to_s,
        message: "科仔AI，2加3等于多少？请只回答结果。",
      },
      options: {
        enforce_membership: true,
        process_inline: false,
      },
    )
  verify!(source_context.success?, "test question could not be sent to public chat: #{source_context.inspect}")
  source = source_context[:message_instance]
  verify!(source.present?, "source chat message is missing")
  source_id = source.id
  rate_key = "kezai:chat-ai:rate:#{user.id}:#{Time.now.to_i / 60}"

  InnoxLan::ChatAI.reply_to(source)
  reply =
    Chat::Message.find_by(
      chat_channel_id: channel.id,
      user_id: bot.id,
      in_reply_to_id: source.id,
    )
  verify!(reply.present?, "AI assistant did not reply in public chat")
  verify!(reply.message.include?("5"), "AI assistant returned an incorrect test answer")
  verify!(reply.message.length <= 1_500, "AI assistant reply is too long")

  puts "AI_CHAT_MODEL=PASS"
  puts "PUBLIC_CHAT_TRIGGER=PASS"
  puts "PUBLIC_CHAT_REPLY=PASS"
  puts "PUBLIC_CHAT_ANSWER=PASS"
  puts "BOT_IDENTITY=PASS"

  raise ActiveRecord::Rollback
end

Discourse.redis.del("kezai:chat-ai:message:#{source_id}") if source_id
Discourse.redis.del(rate_key) if rate_key
puts "ROLLBACK_CLEANUP=PASS"
