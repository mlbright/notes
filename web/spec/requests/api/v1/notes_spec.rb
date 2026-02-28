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

    it "preserves provided created_at and updated_at timestamps" do
      created = "2024-06-15T10:30:00Z"
      updated = "2024-12-01T14:00:00Z"

      post "/api/v1/notes",
        params: { title: "Imported", body: "From memos", created_at: created, updated_at: updated }.to_json,
        headers: headers
      expect(response).to have_http_status(:created)

      json = JSON.parse(response.body)
      expect(Time.parse(json["created_at"])).to be_within(1.second).of(Time.parse(created))
      expect(Time.parse(json["updated_at"])).to be_within(1.second).of(Time.parse(updated))
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

  describe "tagging" do
    it "includes tags in note index response" do
      note = create(:note, user: user, title: "Tagged Note")
      tag = create(:tag, user: user, name: "work")
      note.tags << tag

      get "/api/v1/notes", headers: headers
      json = JSON.parse(response.body)
      note_json = json["notes"].first
      expect(note_json["tags"]).to be_present
      expect(note_json["tags"].first["name"]).to eq("work")
    end

    it "assigns tags on note creation" do
      tag = create(:tag, user: user, name: "important")
      post "/api/v1/notes",
        params: { title: "New", body: "Content", tag_ids: [ tag.id ] }.to_json,
        headers: headers
      expect(response).to have_http_status(:created)

      json = JSON.parse(response.body)
      expect(json["tags"].first["name"]).to eq("important")
    end

    it "updates tags on note update" do
      note = create(:note, user: user)
      tag1 = create(:tag, user: user, name: "old-tag")
      tag2 = create(:tag, user: user, name: "new-tag")
      note.tags << tag1

      patch "/api/v1/notes/#{note.id}",
        params: { tag_ids: [ tag2.id ] }.to_json,
        headers: headers
      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json["tags"].map { |t| t["name"] }).to eq([ "new-tag" ])
    end

    it "prevents assigning other users' tags" do
      other_user = create(:user)
      other_tag = create(:tag, user: other_user, name: "foreign")

      post "/api/v1/notes",
        params: { title: "Test", body: "Content", tag_ids: [ other_tag.id ] }.to_json,
        headers: headers
      expect(response).to have_http_status(:created)

      json = JSON.parse(response.body)
      expect(json["tags"]).to be_empty
    end

    it "includes tags in search results" do
      note = create(:note, user: user, title: "Searchable", body: "Find me")
      tag = create(:tag, user: user, name: "searchable-tag")
      note.tags << tag

      get "/api/v1/notes/search", params: { q: "Searchable" }, headers: headers
      json = JSON.parse(response.body)
      expect(json["notes"].first["tags"]).to be_present
      expect(json["notes"].first["tags"].first["name"]).to eq("searchable-tag")
    end

    it "includes tags in trash results" do
      note = create(:note, :trashed, user: user)
      tag = create(:tag, user: user, name: "trash-tag")
      note.tags << tag

      get "/api/v1/notes/trash", headers: headers
      json = JSON.parse(response.body)
      expect(json["notes"].first["tags"]).to be_present
    end

    it "filters notes by tag name" do
      tag = create(:tag, user: user, name: "priority")
      tagged = create(:note, user: user, title: "Tagged")
      untagged = create(:note, user: user, title: "Untagged")
      tagged.tags << tag

      get "/api/v1/notes", params: { tag: "priority" }, headers: headers
      json = JSON.parse(response.body)
      expect(json["notes"].size).to eq(1)
      expect(json["notes"].first["title"]).to eq("Tagged")
    end
  end
end
