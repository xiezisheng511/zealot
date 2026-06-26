# Be sure to restart your server when you modify this file.

timeout = ENV.fetch('SESSION_TIMEOUT', '180').to_i.minutes

Rails.application.config.session_store :cookie_store, key: '_zealot_session', expire_after: timeout