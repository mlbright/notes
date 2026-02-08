module AuthenticationHelpers
  def sign_in(user)
    session_params = { user_id: user.id, last_seen_at: Time.current }
    allow_any_instance_of(ActionDispatch::Request).to receive(:session).and_return(session_params)
  end

  def api_headers(user)
    user.generate_api_token! unless user.api_token.present?
    { "Authorization" => "Bearer #{user.api_token}", "Content-Type" => "application/json" }
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers
end
