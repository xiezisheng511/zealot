# frozen_string_literal: true

class Users::SsoCallbacksController < ApplicationController
  # 不需要 CSRF 保护，这是外部系统回调

  def callback
    token = params[:access_token]

    if token.blank?
      redirect_to new_user_session_path, alert: 'Token is missing'
      return
    end

    # 调用灵盾接口验证 token 并获取用户信息
    user_info = fetch_user_info(token)

    if user_info.nil?
      Rails.logger.error "[SSO] Failed to fetch user info for token: #{token[0, 10]}..."
      redirect_to new_user_session_path, alert: 'SSO authentication failed'
      return
    end

    # 构建 auth 对象，适配 from_omniauth 的接口
    auth = build_auth_object(user_info, token)

    # 查找或创建用户
    user = User.from_omniauth(auth)

    if user.persisted?
      sign_in user
      session[:created_at] = Time.current
      redirect_to root_path, notice: 'Signed in successfully'
    else
      redirect_to new_user_session_path, alert: 'SSO user creation failed'
    end
  rescue StandardError => e
    Rails.logger.error "[SSO] Error: #{e.message}"
    redirect_to new_user_session_path, alert: 'SSO authentication error'
  end

  private

  # 调用灵盾接口获取用户信息
  # GET /api/auths/{auth}
  # 返回: { id, user_id, created_at, expired_at, user: { id, account, avatar, platform, platform_user_id, dingtalk_user_id, phone, realname, gender, email, role } }
  def fetch_user_info(token)
    sso_base_url = ENV.fetch('SSO_BASE_URL', nil)

    if sso_base_url.blank?
      Rails.logger.error '[SSO] SSO_BASE_URL is not configured'
      return nil
    end

    url = "#{sso_base_url}/api/auths/#{token}?backend_id=#{ENV['SSO_BACKEND_ID']}"

    begin
      uri = URI(url)
      response = Net::HTTP.get_response(uri)

      if response.is_a?(Net::HTTPSuccess)
        result = JSON.parse(response.body)
        if result['user'].present?
          result
        else
          Rails.logger.error "[SSO] Invalid response: #{result.inspect}"
          nil
        end
      else
        Rails.logger.error "[SSO] API returned #{response.code}: #{response.body}"
        nil
      end
    rescue => e
      Rails.logger.error "[SSO] Network error: #{e.message}"
      nil
    end
  end

  # 构建 auth 对象，模拟 OmniAuth 的 auth hash 格式
  def build_auth_object(user_info, token)
    user = user_info['user'] || {}

    # 优先使用 user_id（灵盾18位数字），其次用 email，其次用 account
    uid = user_info['user_id'] || user['email'] || user['account']

    # email 可能为空，使用 user_id@ss o.local 作为占位
    email = user['email'].presence || "#{user_info['user_id']}@sso.local"

    OpenStruct.new(
      provider: 'sso',
      uid: uid,
      info: OpenStruct.new(
        email: email,
        name: user['realname'].presence || user['account'] || email.split('@').first,
        nickname: user['realname']
      ),
      credentials: OpenStruct.new(
        token: token,
        expires: false
      )
    )
  end
end
