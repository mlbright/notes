Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
    ENV.fetch("GOOGLE_CLIENT_ID") { Rails.application.credentials.dig(:google, :client_id) },
    ENV.fetch("GOOGLE_CLIENT_SECRET") { Rails.application.credentials.dig(:google, :client_secret) },
    scope: "email,profile",
    prompt: "select_account"
end

OmniAuth.config.allowed_request_methods = [ :post ]
