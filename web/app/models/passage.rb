require "digest"

# A contiguous excerpt of one note's current content, returned by Retrieval
# (see CONTEXT.md). Passages are disposable: a note's Passages are deleted and
# recut whenever its title or body changes, so they are never referenced by id
# outside the app.
class Passage < ApplicationRecord
  belongs_to :note

  serialize :heading_trail, coder: JSON

  # Passages without an embedding from the current model, including ones
  # embedded by a previous model.
  scope :needing_embedding, -> {
    where(embedding_model: nil).or(where.not(embedding_model: Retrieval.embedder.model_key))
  }

  HEADING_SEPARATOR = " › ".freeze

  # The text the model embeds: title and Heading Trail give the excerpt its
  # context. A title-only note's Passage is its title, so that is not repeated.
  def self.embedding_input(title:, heading_trail:, body:)
    context = [ title, heading_trail.join(HEADING_SEPARATOR) ].compact_blank
    context = [] if heading_trail.empty? && body == title
    (context + [ body ]).join("\n\n")
  end

  # Identifies the embedding input, so an unchanged Passage keeps its
  # embedding when its note is recut.
  def self.digest_for(**attributes)
    Digest::SHA256.hexdigest(embedding_input(**attributes))
  end

  # Embeddings are stored as little-endian float32 blobs, the format sqlite-vec
  # reads.
  def self.pack_embedding(vector)
    vector.pack("e*")
  end

  def embedding_input
    self.class.embedding_input(title:, heading_trail:, body:)
  end
end
