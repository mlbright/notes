# Embeds every Passage that lacks an embedding from the current model. Enqueued
# whenever a note is recut and by RetrievalSweepJob; one runs at a time, since
# embedding holds the job worker's GVL and parallel runs would gain nothing.
class EmbedPassagesJob < ApplicationJob
  queue_as :default

  limits_concurrency key: "all", duration: 1.hour

  BATCH_SIZE = 32

  def perform
    embedder = Retrieval.embedder
    last_id = 0

    loop do
      batch = Passage.needing_embedding.where("id > ?", last_id).order(:id).limit(BATCH_SIZE).to_a
      break if batch.empty?

      batch.each { |passage| embed(passage, embedder) }
      last_id = batch.last.id
    end
  rescue Retrieval::Embedder::Unavailable => e
    Rails.logger.warn("EmbedPassagesJob: #{e.message}")
  end

  private

  # A Passage that fails is skipped and retried by the next sweep. Passages are
  # never edited, only deleted and recut, so the row is either unchanged or gone.
  def embed(passage, embedder)
    vector = embedder.embed_document(passage.embedding_input)
    Passage.where(id: passage.id).update_all(embedding: Passage.pack_embedding(vector), embedding_model: embedder.model_key)
  rescue Retrieval::Embedder::Unavailable
    raise
  rescue StandardError => e
    Rails.logger.error("EmbedPassagesJob: could not embed passage #{passage.id}: #{e.class}: #{e.message}")
  end
end
