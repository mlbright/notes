# Stands in for Retrieval::Embedder so specs don't load the real model. Texts
# that mention the same concept (by any of its words) embed close together, so
# specs can exercise semantic matches that share no words with the query. A
# text that mentions no concept gets a direction of its own.
class StandInEmbedder
  DIMENSIONS = 384

  CONCEPTS = {
    car: %w[car auto automobile vehicle],
    insurance: %w[insurance policy premium coverage],
    bread: %w[bread sourdough loaf baking],
    dentist: %w[dentist teeth dental],
    garden: %w[garden tomatoes plants]
  }.freeze

  attr_reader :embedded

  def initialize(failing: false)
    @failing = failing
    @embedded = []
  end

  def model_key
    "stand-in"
  end

  def embed_query(text)
    raise Retrieval::Embedder::Unavailable, "stand-in failure" if @failing

    embed(text)
  end

  def embed_document(text)
    raise Retrieval::Embedder::Unavailable, "stand-in failure" if @failing

    @embedded << text
    embed(text)
  end

  private

  def embed(text)
    words = text.downcase.scan(/[a-z]+/)
    vector = Array.new(DIMENSIONS, 0.0)
    CONCEPTS.each_with_index do |(_, concept_words), index|
      vector[index] = 1.0 if words.intersect?(concept_words)
    end
    vector[CONCEPTS.size + Zlib.crc32(text) % (DIMENSIONS - CONCEPTS.size)] = 1.0 if vector.none?(&:positive?)

    norm = Math.sqrt(vector.sum { |value| value * value })
    vector.map { |value| value / norm }
  end
end

RSpec.configure do |config|
  config.before do
    Retrieval.embedder = StandInEmbedder.new
  end
end
