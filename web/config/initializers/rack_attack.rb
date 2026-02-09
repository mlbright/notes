Rack::Attack.throttle("api/ip", limit: 3000, period: 5.minutes) do |req|
  req.ip if req.path.start_with?("/api/")
end

Rack::Attack.throttle("api/token", limit: 3000, period: 5.minutes) do |req|
  if req.path.start_with?("/api/")
    req.env["HTTP_AUTHORIZATION"]&.split(" ")&.last
  end
end

Rack::Attack.throttled_responder = lambda do |_request|
  [ 429, { "Content-Type" => "application/json" }, [ { error: "Rate limit exceeded. Retry later." }.to_json ] ]
end
