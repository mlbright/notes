require "rails_helper"

RSpec.describe "Sessions", type: :request do
  describe "GET /login" do
    it "offers password sign-in only" do
      get login_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign in")
      expect(response.body).not_to include("/auth/google_oauth2")
    end
  end

  # Google sign-in was retired: its endpoints must not sign anyone in or
  # create an account.
  describe "Google sign-in endpoints" do
    it "are not routed" do
      expect {
        post "/auth/google_oauth2"
        expect(response).to have_http_status(:not_found)

        get "/auth/google_oauth2/callback", params: { code: "anything" }
        expect(response).to have_http_status(:not_found)
      }.not_to change(User, :count)
    end
  end

  describe "POST /login" do
    let(:user) { create(:user) }

    it "signs in with a valid password" do
      post password_login_path, params: { email: user.email, password: "password" }
      expect(response).to redirect_to(notes_path)
    end

    it "rejects a wrong password" do
      post password_login_path, params: { email: user.email, password: "wrong" }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
