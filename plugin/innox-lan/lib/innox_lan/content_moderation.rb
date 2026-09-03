# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "uri"

module ::InnoxLan
  class ContentModeration
    Result = Struct.new(
      :status,
      :categories,
      :latency_ms,
      :trigger_groups,
      :error,
      keyword_init: true,
    ) do
      def safe?
        status == :safe
      end

      def error?
        status == :error
      end

      def review_payload
        {
          status: status.to_s,
          categories: Array(categories),
          trigger_groups: Array(trigger_groups),
          latency_ms: latency_ms,
        }
      end
    end

    MAX_REVIEW_CHARS = 6_000
    CHUNK_CHARS = 1_200
    CACHE_TTL_SECONDS = 1.hour.to_i
    ALLOWED_ENDPOINT_HOSTS = %w[127.0.0.1 172.17.0.1].freeze

    CHAT_TRIGGER_PATTERNS = {
      politics: /(?:中国共产党|共产党|中共|党中央|中央政府|国务院|国家主席|总书记|习近平|毛泽东|邓小平|全国人大|人民代表大会|政协|党委|党支部|纪委|军委|政治局|党政|政府|台独|港独|藏独|疆独|六四|天安门|法轮功)/i,
      abuse: /(?:傻[\s._-]*[逼比笔bB]|煞笔|蠢货|废物|滚(?:蛋|开)?|白痴|脑残|垃圾人|狗东西|狗日的|王八蛋|混蛋|妈的|他妈的|去[\s._-]*你[\s._-]*妈|操[\s._-]*你(?:[\s._-]*妈)?|草[\s._-]*你(?:[\s._-]*妈)?|日[\s._-]*你|草泥马|去死|畜生|贱人|婊子|(?<![A-Za-z])(?:sb|nmsl|cnm|tmd)(?![A-Za-z]))/i,
      illegal_or_harm: /(?:假证|办假证|代办.{0,8}证|诈骗|博彩|赌博|毒品|枪支|炸弹|杀人|自杀|裸聊|色情|约炮|加我微信|私聊转账|先转钱)/i,
      personal_information: /(?:(?<!\d)1[3-9]\d{9}(?!\d)|(?<!\d)\d{17}[\dXx](?![\dXx])|身份证(?:号|号码)?|家庭住址|住在.{0,12}(?:栋|室|号))/i,
    }.freeze

    class << self
      def check_post(text, user_id: nil)
        check(
          text,
          context: :post,
          user_id: user_id,
          trigger_groups: chat_trigger_groups(text),
        )
      end

      def check_chat(text, user_id: nil)
        triggers = chat_trigger_groups(text)
        return Result.new(status: :safe, categories: [], trigger_groups: []) if triggers.empty?

        check(text, context: :chat, user_id: user_id, trigger_groups: triggers)
      end

      def chat_trigger_groups(text)
        normalized = normalize(text)
        CHAT_TRIGGER_PATTERNS.filter_map { |name, pattern| name if normalized.match?(pattern) }
      end

      private

      def check(text, context:, user_id:, trigger_groups: [])
        normalized = normalize(text)
        return Result.new(status: :safe, categories: [], trigger_groups: trigger_groups) if normalized.blank?

        if normalized.length > MAX_REVIEW_CHARS
          return Result.new(
            status: :controversial,
            categories: ["Long content requires manual review"],
            trigger_groups: trigger_groups,
          )
        end

        cache_key = "kezai:moderation:v3:#{Digest::SHA256.hexdigest(normalized)}"
        if (cached = read_cache(cache_key))
          return Result.new(**cached.transform_keys(&:to_sym), trigger_groups: trigger_groups)
        end

        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        results = normalized.scan(/.{1,#{CHUNK_CHARS}}/m).map { |chunk| request_model(chunk) }
        result = combine(results)
        apply_keyword_floor(result, trigger_groups)
        result.latency_ms =
          ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000).round
        result.trigger_groups = trigger_groups
        write_cache(cache_key, result)
        audit_log(context:, user_id:, result:)
        result
      rescue StandardError => e
        Rails.logger.error(
          "[innox-lan] moderation unavailable context=#{context} user_id=#{user_id} error=#{e.class}",
        )
        Result.new(status: :error, categories: [], trigger_groups: trigger_groups, error: e.class.name)
      end

      def request_model(text)
        uri = URI.parse(SiteSetting.innox_ai_moderation_url)
        unless uri.scheme == "http" && ALLOWED_ENDPOINT_HOSTS.include?(uri.host) && uri.port.positive?
          raise ArgumentError, "moderation endpoint is not an allowed local address"
        end

        http = Net::HTTP.new(uri.host, uri.port)
        timeout = SiteSetting.innox_ai_moderation_timeout_seconds.to_i.clamp(2, 30)
        http.open_timeout = 2
        http.read_timeout = timeout
        http.write_timeout = 2

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request.body =
          JSON.generate(
            model: SiteSetting.innox_ai_moderation_model,
            prompt: text,
            stream: false,
            keep_alive: "5m",
            options: {
              num_ctx: 2048,
              num_predict: 48,
              temperature: 0,
            },
          )

        response = http.request(request)
        raise "moderation request failed with #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        payload = JSON.parse(response.body)
        parse_model_response(payload.fetch("response", ""))
      end

      def parse_model_response(raw)
        status_text = raw[/^Safety:\s*(Safe|Unsafe|Controversial)\s*$/i, 1]
        raise "moderation response did not contain a safety decision" if status_text.blank?

        categories_text = raw[/^Categories:\s*(.+)\s*$/i, 1].to_s
        categories =
          if categories_text.blank? || categories_text.casecmp?("none")
            []
          else
            categories_text.split(",").map(&:strip).reject(&:blank?)
          end

        Result.new(status: status_text.downcase.to_sym, categories: categories)
      end

      def combine(results)
        return Result.new(status: :error, categories: []) if results.empty?

        status =
          if results.any? { |result| result.status == :unsafe }
            :unsafe
          elsif results.any? { |result| result.status == :controversial }
            :controversial
          else
            :safe
          end
        Result.new(status: status, categories: results.flat_map(&:categories).uniq)
      end

      def apply_keyword_floor(result, trigger_groups)
        strict_groups = Array(trigger_groups) & %i[abuse illegal_or_harm personal_information]
        return if strict_groups.empty? || !result.safe?

        result.status = :controversial
        result.categories = (Array(result.categories) + ["Keyword policy"]).uniq
      end

      def normalize(text)
        text
          .to_s
          .unicode_normalize(:nfkc)
          .delete("\u200B\u200C\u200D\uFEFF")
          .gsub(/\r\n?/, "\n")
          .strip
      end

      def read_cache(key)
        raw = Discourse.redis.get(key)
        return if raw.blank?

        parsed = JSON.parse(raw)
        {
          status: parsed.fetch("status").to_sym,
          categories: Array(parsed["categories"]),
          latency_ms: parsed["latency_ms"],
        }
      rescue JSON::ParserError, KeyError
        nil
      end

      def write_cache(key, result)
        Discourse.redis.setex(
          key,
          CACHE_TTL_SECONDS,
          JSON.generate(
            status: result.status.to_s,
            categories: Array(result.categories),
            latency_ms: result.latency_ms,
          ),
        )
      rescue StandardError => e
        Rails.logger.warn("[innox-lan] moderation cache write failed error=#{e.class}")
      end

      def audit_log(context:, user_id:, result:)
        Rails.logger.info(
          "[innox-lan] moderation context=#{context} user_id=#{user_id} status=#{result.status} categories=#{Array(result.categories).join("|")} latency_ms=#{result.latency_ms}",
        )
      end
    end
  end

  module ChatCreateMessageModeration
    private

    def save_message(message_instance:)
      InnoxLan::ContentModerationGate.enforce_chat!(message_instance, message_instance.message)
      super
    end
  end

  module ChatUpdateMessageModeration
    private

    def save_message(message:)
      InnoxLan::ContentModerationGate.enforce_chat!(message, message.message)
      super
    end
  end

  class ContentModerationGate
    class << self
      def enforce_chat!(message_record, text)
        return unless SiteSetting.innox_ai_moderation_enabled
        return if message_record.user&.bot?

        result = ContentModeration.check_chat(text, user_id: message_record.user_id)
        return if result.safe?

        message =
          if result.error?
            "审核服务暂时不可用，这条消息尚未发送，请稍后再试。"
          else
            "这条消息包含需要审核的内容，尚未发送。请调整措辞或联系管理员。"
        end
        message_record.errors.add(:message, message)
        raise ActiveRecord::RecordInvalid.new(message_record)
      end
    end
  end
end
