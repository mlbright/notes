require "rails_helper"

RSpec.describe "Api::V1::Passages", type: :request do
  let(:user) { create(:user) }
  let(:headers) { api_headers(user) }

  def json
    JSON.parse(response.body)
  end

  describe "GET /api/v1/passages" do
    it "returns the best-matching Passages with their note" do
      note = create(:note, user:, title: "Car insurance renewal", body: "# Discounts\n\nAsk about the multi-car discount.", archived: true)
      note.tags << create(:tag, user:, name: "finance")
      EmbedPassagesJob.perform_now

      get "/api/v1/passages", params: { q: "auto policy discount" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["ranking"]).to eq("hybrid")
      expect(json["passages"]).to eq([ {
        "text" => "Ask about the multi-car discount.",
        "heading_trail" => [ "Discounts" ],
        "note" => {
          "id" => note.id,
          "title" => "Car insurance renewal",
          "tags" => [ "finance" ],
          "created_at" => note.created_at.as_json,
          "updated_at" => note.updated_at.as_json,
          "archived" => true,
          "owned" => true,
          "url" => "http://www.example.com/notes/#{note.id}"
        }
      } ])
    end

    it "marks Passages from notes shared with the user" do
      shared = create(:note, title: "Car", body: "Car.")
      create(:share, note: shared, user:)

      get "/api/v1/passages", params: { q: "car" }, headers: headers
      expect(json["passages"].map { |passage| passage["note"]["owned"] }).to eq([ false ])
    end

    it "applies filters and the limit" do
      3.times { |i| create(:note, user:, title: "Car #{i}", body: "Car.", updated_at: Time.zone.parse("2026-0#{i + 1}-15")) }

      get "/api/v1/passages", params: { q: "car", updated_after: "2026-02-01", archived: "exclude" }, headers: headers
      expect(json["passages"].map { |passage| passage["note"]["title"] }).to contain_exactly("Car 1", "Car 2")

      get "/api/v1/passages", params: { q: "car", limit: 1 }, headers: headers
      expect(json["passages"].size).to eq(1)
    end

    it "says when results are ranked by wording only" do
      create(:note, user:, title: "Car", body: "Car.")
      Retrieval.embedder = StandInEmbedder.new(failing: true)

      get "/api/v1/passages", params: { q: "car" }, headers: headers
      expect(json["ranking"]).to eq("keyword")
      expect(json["passages"].size).to eq(1)
    end

    it "requires a query" do
      get "/api/v1/passages", params: { q: " " }, headers: headers
      expect(response).to have_http_status(:bad_request)
      expect(json["error"]).to eq("Query parameter 'q' is required")
    end

    it "rejects invalid filters" do
      { archived: "maybe", updated_after: "last week", updated_before: "2026-13-45", limit: "lots" }.each do |name, value|
        get "/api/v1/passages", params: { q: "car", name => value }, headers: headers
        expect(response).to have_http_status(:bad_request), "#{name}=#{value}"
        expect(json["error"]).to start_with(name.to_s)
      end
    end

    it "returns 401 without authentication" do
      get "/api/v1/passages", params: { q: "car" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
