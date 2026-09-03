# frozen_string_literal: true

require "digest"
require "ipaddr"
require "json"

module ::InnoxLan
  class RegistrationsController < ::ApplicationController
    requires_plugin InnoxLan::PLUGIN_NAME

    skip_before_action :redirect_to_login_if_required
    skip_before_action :redirect_to_profile_if_required
    skip_before_action :check_xhr

    MAX_AVATAR_BYTES = 5.megabytes
    MIN_PASSWORD_LENGTH = 8
    USERNAME_PATTERN = /\A[a-z][a-z0-9_]{2,19}\z/i
    MEMBER_ID_FIELD = "kezai_member_id"
    MEMBER_CATEGORY_FIELD = "kezai_member_category"
    REAL_NAME_FIELD = "kezai_real_name"
    OFFICE_FIELD = "kezai_office"
    REAL_NAME_STATUS_FIELD = "kezai_real_name_status"
    REMEMBERED_PROFILE_COOKIE = "kezai_last_profile"

    def new
      return redirect_within_current_origin("/latest") if current_user

      requested_mode = params[:mode].to_s == "register" || request.path.end_with?("/signup") ? :register : :login
      render_registration_page(nil, :ok, pending_invite.present? ? :register : requested_mode)
    end

    def create
      return redirect_within_current_origin("/") if current_user

      RateLimiter.new(nil, "kezai-signup-#{registration_client_ip}", 5, 1.hour).performed!

      username = normalize_username(params[:username])
      password = params[:password].to_s
      real_name = normalize_text(params[:real_name])
      office = normalize_text(params[:office])
      avatar = params[:avatar]
      invite = registration_invite

      validate_registration!(username, password, real_name, office, avatar)
      raise RegistrationError, "该用户名已经被使用，请换一个。" if User.exists?(username_lower: username.downcase)

      user = build_user(username, password, real_name)
      user.save!
      user.activate
      user.update!(approved: true)
      install_identity!(user, real_name, office)
      install_avatar!(user, avatar) if avatar.present?
      ensure_member_identity!(user)
      redeem_invite!(invite, user) if invite
      remember_profile!(user)
      log_on_user(user, replay_anonymous_action: true)
      redirect_within_current_origin("/latest", status: :see_other)
    rescue RateLimiter::LimitExceeded
      render_registration_page("这台设备注册次数过多，请一小时后再试。", :too_many_requests, :register)
    rescue ActiveRecord::RecordInvalid => e
      user&.destroy!
      render_registration_page(friendly_record_error(e), :unprocessable_entity, :register)
    rescue InnoxLan::RegistrationError => e
      user&.destroy!
      render_registration_page(e.message, :unprocessable_entity, :register)
    rescue StandardError => e
      user&.destroy!
      Rails.logger.error("[innox-lan] secure registration failed: #{e.class}: #{e.message}")
      render_registration_page("注册没有完成，请稍后再试。", :internal_server_error, :register)
    end

    def login
      return redirect_within_current_origin("/latest") if current_user

      username = normalize_username(params[:login_username])
      limiter_key = Digest::SHA256.hexdigest("#{registration_client_ip}:#{username.downcase}")
      RateLimiter.new(nil, "kezai-login-#{limiter_key}", 10, 1.hour).performed!

      user = User.find_by(username_lower: username.downcase)
      password = params[:login_password].to_s
      unless user&.active? && user.approved? && user.confirm_password?(password)
        raise RegistrationError, "用户名或密码不正确。"
      end

      ensure_member_identity!(user)
      remember_profile!(user)
      log_on_user(user, replay_anonymous_action: true)
      redirect_within_current_origin(user.admin? ? "/admin" : "/latest", status: :see_other)
    rescue RateLimiter::LimitExceeded
      render_registration_page("登录尝试次数过多，请一小时后再试。", :too_many_requests, :login)
    rescue InnoxLan::RegistrationError => e
      render_registration_page(e.message, :unprocessable_entity, :login)
    rescue StandardError => e
      Rails.logger.warn("[innox-lan] login failed: #{e.class}: #{e.message}")
      render_registration_page("登录没有完成，请稍后再试。", :internal_server_error, :login)
    end

    def account
      return redirect_within_current_origin("/mobile") unless current_user

      member_id, category = ensure_member_identity!(current_user)
      render_account_page(member_id, category)
    end

    private

    def redirect_within_current_origin(path, status: :found)
      response.headers["Location"] = Discourse.base_path(path)
      head status
    end

    def normalize_username(value)
      value.to_s.unicode_normalize.strip
    end

    def registration_client_ip
      cloudflare_ip = request.headers["HTTP_CF_CONNECTING_IP"].to_s.strip
      cloudflare_ray = request.headers["HTTP_CF_RAY"].to_s.strip
      return request.remote_ip if cloudflare_ip.blank? || cloudflare_ray.blank?

      IPAddr.new(cloudflare_ip).to_s
    rescue IPAddr::InvalidAddressError
      request.remote_ip
    end

    def normalize_text(value)
      value.to_s.unicode_normalize.strip.gsub(/\s+/, " ")
    end

    def ensure_member_identity!(user)
      category = user.admin? ? "管理员" : "普通成员"
      prefix = user.admin? ? "A" : "M"
      member_id = "KZ-#{prefix}-#{user.id.to_s.rjust(6, '0')}"

      write_custom_field!(user, MEMBER_ID_FIELD, member_id)
      write_custom_field!(user, MEMBER_CATEGORY_FIELD, category)
      [member_id, category]
    end

    def write_custom_field!(user, name, value)
      UserCustomField.find_or_initialize_by(user_id: user.id, name: name).tap do |field|
        field.value = value
        field.save!
      end
    end

    def remember_profile!(user)
      profile = {
        username: user.username,
        avatar_url: user.avatar_template.gsub("{size}", "160"),
      }
      cookies.encrypted[REMEMBERED_PROFILE_COOKIE] = {
        value: profile.to_json,
        expires: 1.year.from_now,
        httponly: true,
        same_site: :lax,
        secure: request.ssl?,
      }
    end

    def remembered_profile
      raw = cookies.encrypted[REMEMBERED_PROFILE_COOKIE]
      return {} if raw.blank?

      profile = JSON.parse(raw)
      return {} unless profile.is_a?(Hash)

      profile
    rescue JSON::ParserError, ActiveSupport::MessageEncryptor::InvalidMessage
      {}
    end

    def validate_registration!(username, password, real_name, office, avatar)
      unless USERNAME_PATTERN.match?(username)
        raise RegistrationError, "用户名须为 3 至 20 位，以英文字母开头，只能包含字母、数字和下划线。"
      end
      if password.length < MIN_PASSWORD_LENGTH || password.length > User.max_password_length
        raise RegistrationError, "密码须为 12 至 #{User.max_password_length} 位。"
      end
      unless password.match?(/[A-Za-z]/) && password.match?(/\d/)
        raise RegistrationError, "密码必须同时包含英文字母和数字。"
      end
      raise RegistrationError, "请输入真实姓名。" if real_name.blank?
      raise RegistrationError, "真实姓名请控制在 2 到 30 个字。" if real_name.length < 2 || real_name.length > 30
      raise RegistrationError, "请输入所在办公室。" if office.blank?
      raise RegistrationError, "办公室请控制在 2 到 50 个字。" if office.length < 2 || office.length > 50
      unless params[:legal_agreement].to_s == "1"
        raise RegistrationError, "请确认实名信息真实，并同意遵守社区守则。"
      end

      return if avatar.blank?

      raise RegistrationError, "头像不能超过 5MB。" if avatar.size.to_i > MAX_AVATAR_BYTES
      filename = avatar.original_filename.to_s
      content_type = avatar.content_type.to_s
      unless FileHelper.is_supported_image?(filename) && content_type.start_with?("image/")
        raise RegistrationError, "头像只支持常见图片格式。"
      end
    end

    def build_user(username, password, real_name)
      User.new(
        name: real_name,
        username: username,
        email: "#{SecureRandom.hex(16)}@kezai.invalid",
        password: password,
        active: true,
        approved: true,
        registration_ip_address: registration_client_ip,
      )
    end

    def install_identity!(user, real_name, office)
      write_custom_field!(user, REAL_NAME_FIELD, real_name)
      write_custom_field!(user, OFFICE_FIELD, office)
      write_custom_field!(user, REAL_NAME_STATUS_FIELD, "本人承诺真实")
      user.user_profile.update!(location: office)
    end

    def install_avatar!(user, avatar)
      upload = UploadCreator.new(avatar.tempfile, avatar.original_filename).create_for(user.id)
      unless upload&.persisted?
        message = upload&.errors&.full_messages&.first || "头像处理失败，请换一张图片。"
        raise RegistrationError, message
      end

      user.create_user_avatar unless user.user_avatar
      user.user_avatar.update!(custom_upload_id: upload.id)
      user.update!(uploaded_avatar_id: upload.id)
    end

    def friendly_record_error(error)
      messages = error.record.errors.full_messages.join(" ")
      return "该用户名已经被使用，请换一个。" if messages.match?(/username|用户名|taken/i)
      return "密码不符合安全要求，请使用至少 8 位、同时包含字母和数字的密码。" if messages.match?(/password|密码/i)

      "注册资料未通过检查，请确认后重试。"
    end

    def render_registration_page(error = nil, status = :ok, mode = :login)
      token = form_authenticity_token
      error_html = error.present? ? %(<div class="error" role="alert">#{ERB::Util.html_escape(error)}</div>) : ""
      username_value = ERB::Util.html_escape(params[:username].to_s)
      real_name_value = ERB::Util.html_escape(params[:real_name].to_s)
      office_value = ERB::Util.html_escape(params[:office].to_s)
      invite_key = ERB::Util.html_escape(params[:invite_key].presence || params[:invite].presence || pending_invite&.invite_key.to_s)
      mascot_url = Discourse.base_path("/join/assets/kezai-duo-v2.jpg")
      girl_url = Discourse.base_path("/join/assets/kezai-girl-v2.jpg")
      astronaut_url = Discourse.base_path("/join/assets/kezai-astronaut-v2.jpg")
      icon_url = Discourse.base_path("/join/assets/app-icon-v2-192.png")
      download_url = Discourse.base_path("/Kezai-Community-v1.3.apk")
      saved_profile = remembered_profile
      saved_username = saved_profile["username"].to_s
      requested_login_username = params[:login_username].to_s
      login_username = requested_login_username.present? ? requested_login_username : saved_username
      saved_avatar_url = saved_profile["avatar_url"].to_s.presence || icon_url
      visible_login_avatar = login_username.casecmp?(saved_username) ? saved_avatar_url : icon_url
      login_username_value = ERB::Util.html_escape(login_username)
      saved_username_value = ERB::Util.html_escape(saved_username)
      saved_avatar_value = ERB::Util.html_escape(saved_avatar_url)
      visible_login_avatar_value = ERB::Util.html_escape(visible_login_avatar)
      icon_value = ERB::Util.html_escape(icon_url)
      saved_profile_label = saved_username.present? ? "上次使用：#{saved_username}" : "尚未保存账号"
      saved_profile_label_value = ERB::Util.html_escape(saved_profile_label)
      script_nonce = content_security_policy_nonce
      script_source = File.read(File.expand_path("../../../assets/join.js", __dir__))
      manifest_url = Discourse.base_path("/join/assets/manifest-v2.webmanifest")
      initial_mode = mode == :register ? "register" : "login"
      html = <<~HTML
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
          <meta name="theme-color" content="#071d49">
          <meta name="apple-mobile-web-app-capable" content="yes">
          <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
          <meta name="apple-mobile-web-app-title" content="科仔交流社区">
          <link rel="apple-touch-icon" href="#{icon_url}">
          <link rel="manifest" href="#{manifest_url}">
          <title>科仔交流社区</title>
          <style>
            :root{--navy:#071d49;--blue:#1769e0;--coral:#ff5d55;--paper:rgba(255,255,255,.92);--ink:#172033;--muted:#687184;--line:#dce1e8}*{box-sizing:border-box}html,body{margin:0;min-height:100%}body{min-height:100vh;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif;color:var(--ink);background:#eaf2ff}.page{position:relative;min-height:100vh;display:grid;place-items:center;padding:clamp(18px,4vw,48px);overflow:hidden;background:#eaf2ff}.wallpaper{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;object-position:calc(50% + 92px) bottom;filter:saturate(1.1) contrast(1.08);opacity:.98;z-index:0}.page:before{content:"";position:absolute;inset:0;background:linear-gradient(90deg,rgba(245,248,255,.34) 0%,rgba(245,248,255,.16) 24%,rgba(245,248,255,.42) 40%,rgba(245,248,255,.34) 58%,rgba(245,248,255,.08) 76%,rgba(245,248,255,.18) 100%),linear-gradient(180deg,rgba(245,248,255,.12) 0%,rgba(245,248,255,.05) 52%,rgba(245,248,255,.22) 100%);z-index:1;pointer-events:none}.brand{position:absolute;top:clamp(18px,3vw,34px);left:clamp(18px,4vw,54px);display:flex;align-items:center;gap:12px;z-index:2}.brand img{width:58px;height:58px;border-radius:18px;object-fit:cover;box-shadow:0 16px 34px rgba(7,29,73,.16)}.brand-name{font-size:24px;line-height:1;font-weight:850;color:var(--navy)}.brand-sub{margin-top:5px;font-size:11px;letter-spacing:.14em;color:#496482}.card{width:min(432px,calc(100vw - 32px));max-height:calc(100vh - 42px);overflow:auto;border:1px solid rgba(255,255,255,.85);border-radius:28px;padding:30px;background:var(--paper);backdrop-filter:blur(18px);box-shadow:0 34px 90px rgba(13,43,93,.28);z-index:3}.mode-switch{display:grid;grid-template-columns:1fr 1fr;gap:6px;padding:5px;margin-bottom:18px;border-radius:15px;background:#e9eef5}.mode-switch button{border:0;border-radius:11px;padding:11px 8px;background:transparent;color:#6a7486;font-size:15px;font-weight:800;cursor:pointer}.mode-switch button.active{background:#fff;color:var(--navy);box-shadow:0 4px 12px rgba(15,31,60,.1)}.panel[hidden]{display:none}.app-download{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:18px;padding:10px 12px;border:1px solid #c7daf8;border-radius:14px;background:#f0f6ff;text-decoration:none;color:var(--navy);font-size:13px;font-weight:850}.app-download span{display:flex;align-items:center;gap:10px;min-width:0}.app-download img{width:38px;height:38px;border-radius:12px;object-fit:cover;flex:0 0 auto}.app-download em{font-style:normal;color:var(--blue);white-space:nowrap;font-size:12px;font-weight:850}.eyebrow{color:var(--blue);font-size:12px;font-weight:900;letter-spacing:.14em}.card h2{margin:8px 0 8px;font-size:31px;line-height:1.15;color:var(--navy);letter-spacing:0}.intro{margin:0 0 18px;color:var(--muted);font-size:14px;line-height:1.65}.field{margin:14px 0}label{display:block;margin:12px 0 7px;font-size:14px;font-weight:800;color:#17233c}input[type=text],input[type=password],input[type=file]{width:100%;border:1px solid #c6d1e2;border-radius:12px;padding:12px 13px;background:rgba(255,255,255,.9);color:#101828;font-size:16px;outline:0}input[type=file]{padding:9px}input:focus{border-color:var(--blue);box-shadow:0 0 0 4px rgba(23,105,224,.14)}.field-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}.hint{font-size:12px;color:#7b8493;margin-top:6px;line-height:1.5}.error{background:#fff0ef;color:#9c2925;border:1px solid #f1bbb6;border-radius:12px;padding:11px 13px;margin:14px 0}.avatar-stage{display:flex;align-items:center;gap:13px;padding:12px;margin-bottom:15px;border:1px solid rgba(193,205,226,.78);border-radius:14px;background:rgba(248,250,253,.86)}.preview-shell{width:54px;height:54px;border-radius:50%;background:var(--navy);display:grid;place-items:center;overflow:hidden;flex:0 0 auto}.preview{width:100%;height:100%;object-fit:cover}.preview-copy{min-width:0}.preview-title{font-weight:800;color:#263044;margin-bottom:3px;font-size:14px}.preview-name{font-size:12px;color:#748198;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:265px}.agreement{display:flex;align-items:flex-start;gap:9px;margin:15px 0;padding:12px;background:#fff8ec;border:1px solid #f1dfbd;border-radius:12px;color:#4d5666;font-size:12px;line-height:1.55}.agreement input{margin-top:3px;accent-color:var(--blue)}.primary{width:100%;margin-top:4px;border:0;border-radius:13px;padding:14px;background:var(--blue);color:#fff;font-size:16px;font-weight:900;box-shadow:0 14px 28px rgba(23,105,224,.25);cursor:pointer}.primary:hover{background:#0d58c5}.primary:disabled{opacity:.62;cursor:wait}.security-note{margin-top:14px;padding:10px 12px;border-left:3px solid var(--coral);background:rgba(246,248,252,.82);color:#617087;font-size:12px;line-height:1.55}.privacy{text-align:center;font-size:11px;color:#969daa;margin:13px 0 0}@media(max-width:720px){.page{align-items:center;padding:76px 14px 22px}.wallpaper{object-fit:cover;object-position:58% bottom;opacity:.9}.page:before{background:linear-gradient(180deg,rgba(245,248,255,.78) 0%,rgba(245,248,255,.4) 38%,rgba(245,248,255,.18) 100%),linear-gradient(90deg,rgba(245,248,255,.18) 0%,rgba(245,248,255,.46) 50%,rgba(245,248,255,.12) 100%)}.brand{top:18px;left:18px}.brand img{width:50px;height:50px;border-radius:15px}.brand-name{font-size:20px}.card{width:min(100%,420px);padding:22px 18px;border-radius:24px}.card h2{font-size:28px}.field-grid{grid-template-columns:1fr}.app-download span{font-size:12px}.app-download img{width:34px;height:34px}.preview-shell{width:50px;height:50px}}@media(min-width:721px){.card{transform:translateY(8px)}}
          </style>
        </head>
        <body data-initial-mode="#{initial_mode}" data-remembered-username="#{saved_username_value}" data-default-avatar="#{icon_value}">
          <main class="page">
            <img class="wallpaper" src="#{mascot_url}" alt="">
            <div class="brand"><img src="#{icon_url}" alt="科仔形象"><div><div class="brand-name">科仔交流社区</div><div class="brand-sub">KEZAI COMMUNITY</div></div></div>
              <div class="card">
                <div class="mode-switch" role="tablist"><button type="button" data-mode-button="login">已有账号登录</button><button type="button" data-mode-button="register">新成员实名登记</button></div>
                <a class="app-download" href="#{download_url}"><span><img src="#{astronaut_url}" alt="宇航科仔图标">安卓最新版 · 科仔交流社区 v1.3</span><em>下载安装</em></a>
                #{error_html}
                <section class="panel" data-mode-panel="login">
                  <div class="eyebrow">WELCOME BACK</div><h2>登录社区</h2><p class="intro">使用用户名和密码进入。登录状态会保存在当前设备上。</p>
                  <div class="avatar-stage" id="remembered-profile"><div class="preview-shell"><img class="preview" id="login-avatar-preview" src="#{visible_login_avatar_value}" data-remembered-avatar="#{saved_avatar_value}" alt="上次账号头像"></div><div class="preview-copy"><div class="preview-title">上次账号</div><div class="preview-name" id="login-avatar-name">#{saved_profile_label_value}</div></div></div>
                  <form method="post" action="#{Discourse.base_path('/join/login')}" data-submit-form><input type="hidden" name="authenticity_token" value="#{ERB::Util.html_escape(token)}"><div class="field"><label for="login-username">用户名</label><input id="login-username" name="login_username" type="text" minlength="3" maxlength="20" autocomplete="username" value="#{login_username_value}" required></div><div class="field"><label for="login-password">密码</label><input id="login-password" name="login_password" type="password" maxlength="200" autocomplete="current-password" required></div><button class="primary" type="submit">登录并进入社区</button></form>
                  <div class="security-note">请共同维护社区纯净度：不发布广告引流、恶意攻击、低俗擦边、泄露隐私或违法违规内容。</div>
                </section>
                <section class="panel" data-mode-panel="register">
                  <div class="eyebrow">REAL-NAME REGISTRATION</div><h2>新成员登记</h2><p class="intro">账号用于登录，真实姓名和办公室用于社区内部身份对应。带星号内容均为必填。</p>
                  <form method="post" action="#{Discourse.base_path('/join')}" enctype="multipart/form-data" id="join-form" data-submit-form><input type="hidden" name="authenticity_token" value="#{ERB::Util.html_escape(token)}"><input type="hidden" name="invite_key" value="#{invite_key}"><div class="field-grid"><div class="field"><label for="username">用户名 *</label><input id="username" name="username" type="text" minlength="3" maxlength="20" pattern="[A-Za-z][A-Za-z0-9_]{2,19}" autocomplete="username" placeholder="例如 kezai01" value="#{username_value}" required></div><div class="field"><label for="password">密码 *</label><input id="password" name="password" type="password" minlength="8" maxlength="200" autocomplete="new-password" placeholder="至少8位，含字母和数字" required></div></div><div class="field-grid"><div class="field"><label for="real-name">真实姓名 *</label><input id="real-name" name="real_name" type="text" minlength="2" maxlength="30" autocomplete="name" placeholder="请填写本人姓名" value="#{real_name_value}" required></div><div class="field"><label for="office">所在办公室 *</label><input id="office" name="office" type="text" minlength="2" maxlength="50" autocomplete="organization" placeholder="例如 A302" value="#{office_value}" required></div></div><div class="field"><label for="avatar">头像（可选）</label><div class="avatar-stage"><div class="preview-shell"><img class="preview" id="avatar-preview" src="#{icon_url}" alt="当前头像预览"></div><div class="preview-copy"><div class="preview-title">头像预览</div><div class="preview-name" id="avatar-name">未选择时使用系统头像</div></div></div><input id="avatar" name="avatar" type="file" accept="image/jpeg,image/png,image/webp,image/gif"><div class="hint">支持 JPG、PNG、WebP 或 GIF，不超过 5MB。</div></div><label class="agreement"><input name="legal_agreement" type="checkbox" value="1" required><span>我确认填写的是本人真实姓名和实际办公地点，并承诺遵守法律法规与社区守则。此处是内部实名登记，不替代证件或公安身份核验。</span></label><button class="primary" type="submit">完成登记并进入社区</button></form>
                  <div class="privacy">实名资料仅用于社区内部识别与管理 · 请勿共用账号</div>
                </section>
              </div>
          </main>
          <script nonce="#{ERB::Util.html_escape(script_nonce)}">#{script_source}</script>
        </body>
        </html>
      HTML
      render html: html.html_safe, layout: false, status: status
    end

    def pending_invite
      key = params[:invite_key].presence || params[:invite].presence
      return if key.blank?

      Invite.find_by(invite_key: key.to_s.strip)
    end

    def registration_invite
      invite = pending_invite
      if SiteSetting.invite_only && !invite&.redeemable?
        raise RegistrationError, "请使用有效的邀请链接注册；邀请可能已失效或已达到使用次数。"
      end

      invite
    end

    def redeem_invite!(invite, user)
      redeemed_user = invite.redeem(redeeming_user: user)
      raise RegistrationError, "邀请登记没有完成，请重新打开邀请链接后再试。" unless redeemed_user&.id == user.id
    end

    def render_account_page(member_id, category)
      avatar_url = current_user.avatar_template.gsub("{size}", "160")
      registered_name = UserCustomField.find_by(user_id: current_user.id, name: REAL_NAME_FIELD)&.value.presence || current_user.name.presence || current_user.username
      safe_name = ERB::Util.html_escape(registered_name)
      safe_id = ERB::Util.html_escape(member_id)
      safe_category = ERB::Util.html_escape(category)
      office = UserCustomField.find_by(user_id: current_user.id, name: OFFICE_FIELD)&.value.presence || current_user.user_profile&.location.presence || "社区管理办公室"
      safe_office = ERB::Util.html_escape(office)
      html = <<~HTML
        <!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="theme-color" content="#071d49"><title>我的科仔成员编号</title><style>*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px;background:linear-gradient(145deg,#071d49,#0d367d);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif;color:#172033}.card{width:min(100%,450px);background:#fff;border-radius:26px;padding:32px;text-align:center;box-shadow:0 28px 80px rgba(0,0,0,.34)}.avatar{width:94px;height:94px;border-radius:50%;object-fit:cover;box-shadow:0 0 0 4px #fff,0 0 0 7px #1769e0}.eyebrow{margin-top:22px;color:#1769e0;font-size:12px;font-weight:850;letter-spacing:.12em}h1{margin:8px 0 4px;font-size:28px}.meta{color:#737b86;margin:5px 0}.verified{display:inline-block;margin:14px 0 22px;padding:7px 11px;border-radius:999px;background:#eaf7ef;color:#237743;font-size:12px;font-weight:750}.id-label{font-size:12px;color:#858d97}.member-id{font-size:22px;font-weight:850;letter-spacing:.045em;margin:6px 0 26px;overflow-wrap:anywhere}.actions{display:grid;grid-template-columns:1fr 1fr;gap:10px}.actions a{text-decoration:none;border-radius:12px;padding:13px 10px;font-weight:750}.primary{background:#1769e0;color:#fff}.secondary{background:#f1f3f6;color:#222831}.note{font-size:12px;color:#8a919b;line-height:1.6;margin-top:18px}</style></head><body><main class="card"><img class="avatar" src="#{avatar_url}" alt="#{safe_name}的头像"><div class="eyebrow">KEZAI MEMBER</div><h1>#{safe_name}</h1><div class="meta">#{safe_category} · #{safe_office}</div><div class="verified">已完成内部实名登记</div><div class="id-label">成员编号</div><div class="member-id">#{safe_id}</div><div class="actions"><a class="primary" href="#{Discourse.base_path('/latest')}">进入论坛</a><a class="secondary" href="#{Discourse.base_path('/chat')}">公屏聊天</a></div><div class="note">成员编号与账号永久对应；请勿把账号和密码交给他人使用。</div></main></body></html>
      HTML
      render html: html.html_safe, layout: false
    end
  end

  class RegistrationError < StandardError
  end
end
