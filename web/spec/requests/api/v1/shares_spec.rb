require "rails_helper"

RSpec.describe "Api::V1::Shares", type: :request do
  let(:owner) { create(:user) }
  let(:recipient) { create(:user) }
  let(:headers) { api_headers(owner) }
  let(:note) { create(:note, user: owner) }

  describe "GET /api/v1/notes/:note_id/shares" do
    it "lists shares for a note" do
      create(:share, note: note, user: recipient)

      get "/api/v1/notes/#{note.id}/shares", headers: headers
      json = JSON.parse(response.body)
      expect(json.size).to eq(1)
    end
  end

  describe "POST /api/v1/notes/:note_id/shares" do
    it "shares a note with another user" do
      post "/api/v1/notes/#{note.id}/shares",
        params: { email: recipient.email }.to_json,
        headers: headers
      expect(response).to have_http_status(:created)
    end

    it "returns 404 for unknown user email" do
      post "/api/v1/notes/#{note.id}/shares",
        params: { email: "nobody@example.com" }.to_json,
        headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "prevents non-owners from sharing" do
      other_headers = api_headers(recipient)
      create(:share, note: note, user: recipient)

      post "/api/v1/notes/#{note.id}/shares",
        params: { email: create(:user).email }.to_json,
        headers: other_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /api/v1/notes/:note_id/shares/:id" do
    it "revokes a share" do
      share = create(:share, note: note, user: recipient)
      delete "/api/v1/notes/#{note.id}/shares/#{share.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(note.shares.count).to eq(0)
    end
  end
end
