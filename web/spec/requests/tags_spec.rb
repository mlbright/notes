require "rails_helper"

RSpec.describe "Tags", type: :request do
  let(:user) { create(:user, :password_user) }

  before do
    post password_login_path, params: { email: user.email, password: "password" }
  end

  describe "GET /tags" do
    it "lists the current user's tags" do
      create(:tag, user: user, name: "work")
      create(:tag, name: "other-user-tag")

      get tags_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("work")
      expect(response.body).not_to include("other-user-tag")
    end
  end

  describe "POST /tags" do
    it "creates a new tag" do
      expect {
        post tags_path, params: { tag: { name: "Important", color: "#ff0000" } }
      }.to change(Tag, :count).by(1)

      tag = user.tags.last
      expect(tag.name).to eq("important")
      expect(tag.color).to eq("#ff0000")
    end

    it "rejects duplicate tag names" do
      create(:tag, user: user, name: "work")
      expect {
        post tags_path, params: { tag: { name: "Work" } }
      }.not_to change(Tag, :count)
    end

    it "responds with turbo_stream" do
      post tags_path, params: { tag: { name: "urgent", color: "#ff0000" } },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("urgent")
    end
  end

  describe "GET /tags/:id/edit" do
    it "renders the edit form" do
      tag = create(:tag, user: user)
      get edit_tag_path(tag)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /tags/:id" do
    it "updates a tag" do
      tag = create(:tag, user: user, name: "old")
      patch tag_path(tag), params: { tag: { name: "new" } }
      expect(response).to redirect_to(tags_path)
      expect(tag.reload.name).to eq("new")
    end

    it "renders edit on validation failure" do
      tag = create(:tag, user: user, name: "existing")
      create(:tag, user: user, name: "taken")
      patch tag_path(tag), params: { tag: { name: "taken" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /tags/:id" do
    it "deletes a tag" do
      tag = create(:tag, user: user)
      expect { delete tag_path(tag) }.to change(Tag, :count).by(-1)
    end

    it "responds with turbo_stream" do
      tag = create(:tag, user: user)
      delete tag_path(tag), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    end
  end
end
