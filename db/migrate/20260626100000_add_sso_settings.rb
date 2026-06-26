# frozen_string_literal: true

class AddSsoSettings < ActiveRecord::Migration[7.2]
  def change
    # SSO 配置项
    # 设置项通过 EnvironmentVariable 或 rails settings UI 配置
    # 使用方式: Setting.sso 或 ENV['SSO_BASE_URL']
  end
end
