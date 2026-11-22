require "rails_helper"

RSpec.describe "Notes", type: :request do
  let(:user) { create(:user, :password_user) }

  before do
    post password_login_path, params: { email: user.email, password: "password" }
  end

  describe "GET /notes" do
    # Cards preview the start of a note; they must render it like the note
    # page does, not from HTML-escaped text.
    it "renders card previews with the same markdown as the note page" do
      create(:note, user: user, body: "> quoted line\n\nssh <host>")

      get notes_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<blockquote>")
      expect(response.body).to include("ssh &lt;host&gt;")
      expect(response.body).not_to include("&amp;lt;host")
    end
  end
end
