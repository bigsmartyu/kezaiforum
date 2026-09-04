# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module ::InnoxLan
  class ChatAI
    TRIGGER_PATTERN = /(?:@kezai_ai\b|@?科仔\s*(?:AI|ai|助手))/i
    ALLOWED_ENDPOINT_HOSTS = %w[127.0.0.1 172.17.0.1].freeze
    MAX_QUESTION_CHARS = 1_000
    MAX_REPLY_CHARS = 1_500
    HISTORY_LIMIT = 6
    RATE_LIMIT_PER_MINUTE = 6

    class << self
      def triggered?(text)
        text.to_s.match?(TRIGGER_PATTERN)
      end

      def reply_to(message)
        return unless SiteSetting.innox_ai_chat_enabled
        return if message.blank? || message.user&.bot? || message.user&.anonymous?

        channel = message.chat_channel
        return if channel.blank? || channel.direct_message_channel?
        return unless triggered?(message.message)
        return unless claim_message(message.id)

        reply = build_reply(message)
        publish_reply(message, reply)
      rescue StandardError => e
        Rails.logger.error(
          "[innox-lan] chat AI failed message_id=#{message&.id} error=#{e.class}: #{e.message}",
        )
        publish_reply(message, "科仔 AI 暂时无法回答，请稍后再试。") if message&.persisted?
      end

      private

      def build_reply(message)
        return "提问有点频繁，请稍等一分钟后再试。" unless within_rate_limit?(message.user_id)

        question =
          message.message.to_s.gsub(TRIGGER_PATTERN, " ").gsub(/\s+/, " ").strip.first(
            MAX_QUESTION_CHARS,
          )
        return "我在，请在点名后写下你的问题。" if question.blank?

        input_review = ContentModeration.check_post(question, user_id: message.user_id)
        unless input_review.safe?
          return input_review.error? ? "审核服务暂时不可用，请稍后再问。" :
                   "这个问题不适合在公开群聊中回答，请换一个合规的问题。"
        end

        answer = request_model(message, question)
        return "我暂时没有生成有效回答，请换一种问法。" if answer.blank?

        output_review = ContentModeration.check_post(answer, user_id: SiteSetting.innox_ai_chat_bot_username)
        return answer if output_review.safe?

        output_review.error? ? "审核服务暂时不可用，请稍后再问。" :
          "这个回答可能不适合公开发送，我先不展示。"
      end

      def request_model(message, question)
        uri = URI.parse(SiteSetting.innox_ai_chat_url)
        unless uri.scheme == "http" && ALLOWED_ENDPOINT_HOSTS.include?(uri.host) && uri.port.positive?
          raise ArgumentError, "chat endpoint is not an allowed local address"
        end

        history =
          Chat::Message
            .where(chat_channel_id: message.chat_channel_id)
            .where("id < ?", message.id)
            .order(id: :desc)
            .limit(HISTORY_LIMIT)
            .reverse
            .map do |item|
              {
                role: item.user&.username == SiteSetting.innox_ai_chat_bot_username ? "assistant" : "user",
                content: item.message.to_s.first(MAX_QUESTION_CHARS),
              }
            end

        messages =
          [
            {
              role: "system",
              content:
                "你是科仔交流社区的公开群聊助手。请用简短、友好、准确的中文回答，通常不超过200字。" \
                  "你不是管理员，不能批准账号、代表公司承诺或编造社区信息；不知道时要明确说不知道。" \
                  "不要提供违法、有害、辱骂、政治煽动、隐私泄露或绕过审核的内容。",
            },
          ] + history + [{ role: "user", content: question }]

        http = Net::HTTP.new(uri.host, uri.port)
        timeout = SiteSetting.innox_ai_chat_timeout_seconds.to_i.clamp(5, 60)
        http.open_timeout = 2
        http.read_timeout = timeout
        http.write_timeout = 3

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request.body =
          JSON.generate(
            model: SiteSetting.innox_ai_chat_model,
            messages: messages,
            stream: false,
            think: false,
            keep_alive: "5m",
            options: {
              num_ctx: 2_048,
              num_predict: 256,
              temperature: 0.35,
            },
          )

        response = http.request(request)
        raise "chat request failed with #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        payload = JSON.parse(response.body)
        payload.dig("message", "content").to_s.strip.first(MAX_REPLY_CHARS)
      end

      def publish_reply(source_message, text)
        bot = User.find_by(username_lower: SiteSetting.innox_ai_chat_bot_username.downcase)
        raise "chat bot account is missing" if bot.blank? || !bot.bot?

        visible_text = "🤖 科仔 AI：#{text}".first(MAX_REPLY_CHARS)

        context =
          Chat::CreateMessage.call(
            guardian: Guardian.new(bot),
            params: {
              chat_channel_id: source_message.chat_channel_id.to_s,
              message: visible_text,
              in_reply_to_id: source_message.id.to_s,
            },
            options: {
              enforce_membership: true,
              process_inline: false,
            },
          )
        raise "chat reply could not be created" unless context.success?

        context
      end

      def claim_message(message_id)
        Discourse.redis.set(
          "kezai:chat-ai:message:#{message_id}",
          "1",
          nx: true,
          ex: 1.day.to_i,
        )
      end

      def within_rate_limit?(user_id)
        key = "kezai:chat-ai:rate:#{user_id}:#{Time.now.to_i / 60}"
        count = Discourse.redis.incr(key)
        Discourse.redis.expire(key, 90) if count == 1
        count <= RATE_LIMIT_PER_MINUTE
      end
    end
  end
end

module ::Jobs
  class KezaiChatReply < ::Jobs::Base
    def execute(args)
      message = ::Chat::Message.find_by(id: args[:chat_message_id])
      InnoxLan::ChatAI.reply_to(message) if message
    end
  end
end
