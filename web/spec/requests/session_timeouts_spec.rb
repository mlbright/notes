require "rails_helper"

RSpec.describe "SessionTimeouts", type: :request do
  let(:user) { create(:user, :password_user) }

  before do
    post password_login_path, params: { email: user.email, password: "password" }
  end

  describe "GET /session_timeout/edit" do
    it "renders the edit form" do
      get edit_session_timeout_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /session_timeout" do
    it "updates the session timeout" do
      patch session_timeout_path, params: { session_timeout: 86_400 }
      expect(response).to redirect_to(notes_path)
      expect(user.reload.session_timeout).to eq(86_400)
    end

    it "rejects invalid timeout values" do
      patch session_timeout_path, params: { session_timeout: 0 }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
