require "rails_helper"

RSpec.describe "Api::V1::Notes", type: :request do
  let(:user) { create(:user) }
  let(:headers) { api_headers(user) }

  describe "GET /api/v1/notes" do
    it "returns the user's active notes" do
      create(:note, user: user, title: "My Note")
      create(:note, :trashed, user: user, title: "Trashed")

      get "/api/v1/notes", headers: headers
      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json["notes"].size).to eq(1)
      expect(json["notes"].first["title"]).to eq("My Note")
      expect(json["pagination"]).to be_present
    end

    it "returns 401 without authentication" do
      get "/api/v1/notes"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/notes" do
    it "creates a new note" do
      post "/api/v1/notes", params: { title: "New", body: "Content" }.to_json, headers: headers
      expect(response).to have_http_status(:created)

      json = JSON.parse(response.body)
      expect(json["title"]).to eq("New")
      expect(json["body"]).to eq("Content")
    end

    it "returns errors for invalid note" do
      post "/api/v1/notes", params: { body: "x" * 40_000 }.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/notes/:id" do
    it "returns a specific note" do
      note = create(:note, user: user)
      get "/api/v1/notes/#{note.id}", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for another user's note" do
      other_note = create(:note)
      get "/api/v1/notes/#{other_note.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "returns shared notes" do
      other = create(:user)
      note = create(:note, user: other)
      create(:share, note: note, user: user)

      get "/api/v1/notes/#{note.id}", headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /api/v1/notes/:id" do
    it "updates a note" do
      note = create(:note, user: user)
      patch "/api/v1/notes/#{note.id}", params: { title: "Updated" }.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(note.reload.title).to eq("Updated")
    end
  end

  describe "DELETE /api/v1/notes/:id" do
    it "soft deletes a note" do
      note = create(:note, user: user)
      delete "/api/v1/notes/#{note.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(note.reload.trashed?).to be true
    end

    it "permanently deletes a trashed note" do
      note = create(:note, :trashed, user: user)
      expect { delete "/api/v1/notes/#{note.id}", headers: headers }.to change(Note, :count).by(-1)
    end

    it "prevents non-owners from deleting" do
      owner = create(:user)
      note = create(:note, user: owner)
      create(:share, note: note, user: user)

      delete "/api/v1/notes/#{note.id}", headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /api/v1/notes/:id/restore" do
    it "restores a trashed note" do
      note = create(:note, :trashed, user: user)
      patch "/api/v1/notes/#{note.id}/restore", headers: headers
      expect(response).to have_http_status(:ok)
      expect(note.reload.trashed?).to be false
    end
  end

  describe "PATCH /api/v1/notes/:id/archive" do
    it "archives a note" do
      note = create(:note, user: user)
      patch "/api/v1/notes/#{note.id}/archive", headers: headers
      expect(response).to have_http_status(:ok)
      expect(note.reload.archived?).to be true
    end
  end

  describe "PATCH /api/v1/notes/:id/toggle_pin" do
    it "toggles pin state" do
      note = create(:note, user: user, pinned: false)
      patch "/api/v1/notes/#{note.id}/toggle_pin", headers: headers
      expect(note.reload.pinned?).to be true
    end
  end

  describe "POST /api/v1/notes/:id/duplicate" do
    it "duplicates a note" do
      note = create(:note, user: user, title: "Original")
      post "/api/v1/notes/#{note.id}/duplicate", headers: headers
      expect(response).to have_http_status(:created)

      json = JSON.parse(response.body)
      expect(json["title"]).to eq("Original (copy)")
    end
  end

  describe "GET /api/v1/notes/search" do
    it "searches notes by query" do
      create(:note, user: user, title: "Ruby on Rails", body: "A web framework")
      create(:note, user: user, title: "Python", body: "A programming language")

      get "/api/v1/notes/search", params: { q: "Ruby" }, headers: headers
      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json["notes"].size).to eq(1)
    end

    it "returns error without query" do
      get "/api/v1/notes/search", headers: headers
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /api/v1/notes/trash" do
    it "returns trashed notes" do
      create(:note, user: user)
      trashed = create(:note, :trashed, user: user)

      get "/api/v1/notes/trash", headers: headers
      json = JSON.parse(response.body)
      expect(json["notes"].size).to eq(1)
      expect(json["notes"].first["id"]).to eq(trashed.id)
    end
  end

  describe "GET /api/v1/notes/:id/export" do
    it "returns note as markdown" do
      note = create(:note, user: user, title: "Export Me", body: "Content")
      get "/api/v1/notes/#{note.id}/export", headers: headers
      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json["content"]).to include("# Export Me")
      expect(json["content"]).to include("Content")
    end
  end
end
