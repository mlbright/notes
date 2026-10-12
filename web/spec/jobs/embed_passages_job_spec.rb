require "rails_helper"

RSpec.describe EmbedPassagesJob, type: :job do
  let(:note) { create(:note, title: "Car", body: "One.\n\n# Two\n\nTwo.") }

  it "embeds every Passage missing a current embedding" do
    note
    EmbedPassagesJob.perform_now

    expect(note.passages.pluck(:embedding_model)).to all(eq("stand-in"))
    expect(note.passages.first.embedding.bytesize).to eq(StandInEmbedder::DIMENSIONS * 4)
  end

  it "re-embeds Passages embedded by another model and leaves current ones alone" do
    note
    EmbedPassagesJob.perform_now
    note.passages.first.update_columns(embedding_model: "old-model")
    Retrieval.embedder = embedder = StandInEmbedder.new

    EmbedPassagesJob.perform_now

    expect(embedder.embedded).to eq([ note.passages.first.embedding_input ])
  end

  it "skips a Passage that fails and carries on" do
    note
    embedder = StandInEmbedder.new
    allow(embedder).to receive(:embed_document).and_call_original
    allow(embedder).to receive(:embed_document).with(note.passages.first.embedding_input).and_raise(RuntimeError, "bad input")
    Retrieval.embedder = embedder

    EmbedPassagesJob.perform_now

    expect(note.passages.map(&:embedding_model)).to eq([ nil, "stand-in" ])
  end

  it "gives up quietly when the model is not installed" do
    note
    Retrieval.embedder = StandInEmbedder.new(failing: true)

    expect { EmbedPassagesJob.perform_now }.not_to raise_error
    expect(note.passages.pluck(:embedding_model)).to all(be_nil)
  end
end
