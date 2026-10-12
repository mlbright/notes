require "rails_helper"

RSpec.describe "Api::V1::Auth", type: :request do
  let(:json_headers) { { "Content-Type" => "application/json" } }

  describe "POST /api/v1/auth/token" do
    let(:password_user) { create(:user, :password_user) }
    let(:oauth_user) { create(:user) }

    it "issues a token for a valid email and password" do
      post "/api/v1/auth/token", params: { email: password_user.email, password: "password" }.to_json, headers: json_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["token"]).to eq(password_user.reload.api_token)
    end

    it "rejects a wrong password" do
      post "/api/v1/auth/token", params: { email: password_user.email, password: "wrong" }.to_json, headers: json_headers
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an email with no credential" do
      post "/api/v1/auth/token", params: { email: password_user.email }.to_json, headers: json_headers
      expect(response).to have_http_status(:unauthorized)
      expect(password_user.reload.api_token).to be_nil
    end

    it "rejects an email with a blank uid" do
      post "/api/v1/auth/token", params: { email: password_user.email, uid: "" }.to_json, headers: json_headers
      expect(response).to have_http_status(:unauthorized)
      expect(password_user.reload.api_token).to be_nil
    end

    it "issues a token for a matching email and OAuth uid" do
      post "/api/v1/auth/token", params: { email: oauth_user.email, uid: oauth_user.uid }.to_json, headers: json_headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/auth/refresh" do
    let(:user) { create(:user) }

    it "extends a valid token" do
      user.generate_api_token!
      user.update!(token_expires_at: 1.day.from_now)

      post "/api/v1/auth/refresh", headers: api_headers(user)
      expect(response).to have_http_status(:ok)
      expect(user.reload.token_expires_at).to be > 29.days.from_now
    end

    it "rejects an expired token" do
      user.update!(api_token: "expired-token", token_expires_at: 1.day.ago)

      post "/api/v1/auth/refresh", headers: { "Authorization" => "Bearer expired-token" }
      expect(response).to have_http_status(:unauthorized)
      expect(user.reload.api_token).to eq("expired-token")
    end

    it "rejects a request with no token when a user has none" do
      user

      post "/api/v1/auth/refresh"
      expect(response).to have_http_status(:unauthorized)
      expect(user.reload.api_token).to be_nil
    end
  end
end
