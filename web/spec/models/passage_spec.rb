require "rails_helper"

RSpec.describe Passage, type: :model do
  it { is_expected.to belong_to(:note) }

  describe ".embedding_input" do
    it "puts the title and Heading Trail before the text" do
      input = Passage.embedding_input(title: "Backups", heading_trail: [ "S3", "Retention" ], body: "Thirty days.")
      expect(input).to eq("Backups\n\nS3 › Retention\n\nThirty days.")
    end

    it "leaves out a missing title or empty Heading Trail" do
      expect(Passage.embedding_input(title: nil, heading_trail: [], body: "Text.")).to eq("Text.")
    end

    it "does not repeat the title of a title-only note" do
      expect(Passage.embedding_input(title: "Call the plumber", heading_trail: [], body: "Call the plumber")).to eq("Call the plumber")
    end
  end

  describe ".digest_for" do
    it "changes when any part of the embedding input changes" do
      base = { title: "T", heading_trail: [ "H" ], body: "B" }
      digest = Passage.digest_for(**base)

      expect(Passage.digest_for(**base)).to eq(digest)
      expect(Passage.digest_for(**base, title: "U")).not_to eq(digest)
      expect(Passage.digest_for(**base, heading_trail: [ "I" ])).not_to eq(digest)
      expect(Passage.digest_for(**base, body: "C")).not_to eq(digest)
    end
  end

  describe ".needing_embedding" do
    let(:note) { create(:note, body: "One.\n\n# Two\n\nTwo.\n\n# Three\n\nThree.") }

    it "finds Passages with no embedding or one from another model" do
      missing, stale, current = note.passages.to_a
      stale.update_columns(embedding: Passage.pack_embedding([ 1.0 ]), embedding_model: "old-model")
      current.update_columns(embedding: Passage.pack_embedding([ 1.0 ]), embedding_model: Retrieval.embedder.model_key)

      expect(Passage.needing_embedding).to contain_exactly(missing, stale)
    end
  end
end
