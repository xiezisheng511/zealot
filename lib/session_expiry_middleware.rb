class SessionExpiryMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)

    if request.session[:user_id] && request.session[:created_at]
      session_age = Time.current - request.session[:created_at]
      timeout = ENV.fetch('SESSION_TIMEOUT', '180').to_i.minutes

      if session_age > timeout
        request.session.clear
        return redirect_to_new_session(request)
      end
    end

    @app.call(env)
  end

  private

  def redirect_to_new_session(request)
    if request.xhr?
      [401, { 'Content-Type' => 'application/json' }, [{ error: 'Session expired' }.to_json]]
    else
      [302, { 'Location' => '/users/sign_in' }, []]
    end
  end
end