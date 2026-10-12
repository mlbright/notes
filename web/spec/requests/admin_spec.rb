require "rails_helper"

RSpec.describe "Admin", type: :request do
  let(:admin) { create(:user, :password_user, :admin) }

  before do
    post password_login_path, params: { email: admin.email, password: "password" }
  end

  describe "GET /admin" do
    it "shows how far Retrieval has caught up" do
      create(:note, user: admin, title: "Embedded", body: "Text.")
      EmbedPassagesJob.perform_now
      create(:note, user: admin, title: "Pending", body: "Text.")
      allow(Retrieval::Embedder).to receive(:installed?).and_return(false)

      get admin_dashboard_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1 / 2")
      expect(response.body).to include("notes embedded")
      expect(response.body).to include("missing — run make update")
      expect(response.body).to include("not yet run")
    end
  end
end
