require "rails_helper"

# Runs the real model, so it needs `bin/rails retrieval:install_model` first and
# is skipped otherwise. Every other spec uses StandInEmbedder.
RSpec.describe Retrieval::Embedder do
  let(:user) { create(:user) }

  before do
    skip "embedding model not installed; run bin/rails retrieval:install_model" unless described_class.installed?
    Retrieval.embedder = described_class.new
  end

  it "finds a note by meaning when it shares no words with the query" do
    insurance = create(:note, user:, title: "Car insurance renewal", body: "Premium went up to $1,240; renews on 3 March.")
    create(:note, user:, title: "Sourdough", body: "Feed the starter the night before. 500g flour, 350g water.")
    create(:note, user:, title: "Dentist", body: "Tuesday at 4pm. Bring the referral letter.")
    EmbedPassagesJob.perform_now

    result = Retrieval.new(user:, query: "auto policy").call

    expect(Passage.where(embedding_model: Retrieval.embedder.model_key).count).to eq(3)
    expect(result.ranking).to eq("hybrid")
    expect(result.passages.map(&:note)).to eq([ insurance ])
  end

  it "produces normalised 384-dimension embeddings" do
    vector = Retrieval.embedder.embed_query("auto policy")

    expect(vector.size).to eq(384)
    expect(Math.sqrt(vector.sum { |value| value * value })).to be_within(1e-4).of(1.0)
  end
end
