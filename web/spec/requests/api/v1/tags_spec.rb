require "rails_helper"

RSpec.describe "Api::V1::Tags", type: :request do
  let(:user) { create(:user) }
  let(:headers) { api_headers(user) }

  describe "GET /api/v1/tags" do
    it "returns user's tags" do
      create(:tag, user: user, name: "work")
      create(:tag, name: "other-user-tag")

      get "/api/v1/tags", headers: headers
      json = JSON.parse(response.body)
      expect(json.size).to eq(1)
      expect(json.first["name"]).to eq("work")
    end
  end

  describe "POST /api/v1/tags" do
    it "creates a new tag" do
      post "/api/v1/tags", params: { name: "Important", color: "#ff0000" }.to_json, headers: headers
      expect(response).to have_http_status(:created)

      json = JSON.parse(response.body)
      expect(json["name"]).to eq("important")
      expect(json["color"]).to eq("#ff0000")
    end

    it "prevents duplicate tag names per user" do
      create(:tag, user: user, name: "work")
      post "/api/v1/tags", params: { name: "Work" }.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/tags/:id" do
    it "updates a tag" do
      tag = create(:tag, user: user, name: "old")
      patch "/api/v1/tags/#{tag.id}", params: { name: "new" }.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(tag.reload.name).to eq("new")
    end
  end

  describe "DELETE /api/v1/tags/:id" do
    it "deletes a tag" do
      tag = create(:tag, user: user)
      expect { delete "/api/v1/tags/#{tag.id}", headers: headers }.to change(Tag, :count).by(-1)
    end
  end
end
