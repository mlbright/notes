# Finds the Passages most relevant to a query, by meaning as well as wording,
# among the notes a user can access (see CONTEXT.md). Keyword matches come from
# the Passages' FTS5 index and semantic matches from comparing embeddings; the
# two rankings are merged with reciprocal rank fusion.
class Retrieval
  DEFAULT_LIMIT = 8
  MAX_LIMIT = 50
  MAX_PER_NOTE = 3
  ARCHIVED_OPTIONS = %w[include exclude only].freeze

  # How many of the best matches each ranking contributes before merging.
  CANDIDATES = 50

  # Semantic-only matches below this cosine similarity are dropped. Measured on
  # sample notes with bge-small-en-v1.5, relevant passages scored 0.55 and up
  # while 90% of unrelated ones scored under 0.51, so this only cuts clear
  # misses. Passages that also match by keyword are always kept.
  MIN_SIMILARITY = 0.5

  # Reciprocal rank fusion constant; the conventional value.
  RRF_K = 60

  # The keyword side ignores these unless the query is made of nothing else.
  STOPWORDS = %w[
    a about an and are as at be been but by can could did do does for from had
    has have how i if in into is it its me my no not of on or our should so
    that the their them then there these they this those to was we were what
    when where which who why will with would you your
  ].to_set.freeze

  Result = Data.define(:passages, :ranking)
  Status = Data.define(:notes_total, :notes_embedded, :model, :model_installed, :last_sweep_at)

  class << self
    attr_writer :embedder

    # One per process, shared by its threads; tests swap in a stand-in.
    def embedder
      @embedder ||= Embedder.new
    end

    # How far embedding has caught up, for the admin dashboard. Reads only the
    # database and filesystem; never loads the model.
    def status
      notes = Note.where(trashed: false)
      Status.new(
        notes_total: notes.count,
        notes_embedded: notes.where(passages_version: Passage::Cutter::VERSION)
          .where.not(id: Passage.needing_embedding.select(:note_id)).count,
        model: embedder.model_key,
        model_installed: Embedder.installed?,
        last_sweep_at: RetrievalSweepJob.last_run_at
      )
    end
  end

  def initialize(user:, query:, tag: nil, archived: "include", updated_after: nil, updated_before: nil, limit: DEFAULT_LIMIT)
    @user = user
    @query = query.to_s
    @tag = tag
    @archived = archived
    @updated_after = updated_after
    @updated_before = updated_before
    @limit = limit.clamp(1, MAX_LIMIT)
  end

  def call
    keyword_ids = keyword_matches
    semantic, ranking = semantic_matches

    scores = Hash.new(0.0)
    keyword_ids.each_with_index { |id, rank| scores[id] += 1.0 / (RRF_K + rank + 1) }
    semantic.each_with_index do |(id, distance), rank|
      next if 1 - distance < MIN_SIMILARITY && !scores.key?(id)
      scores[id] += 1.0 / (RRF_K + rank + 1)
    end

    Result.new(passages: best(scores), ranking:)
  end

  private

  def notes
    notes = @user.accessible_notes.where(trashed: false)
    notes = notes.where(archived: false) if @archived == "exclude"
    notes = notes.where(archived: true) if @archived == "only"
    notes = notes.where(id: NoteTag.joins(:tag).where(tags: { name: @tag.to_s.strip.downcase }).select(:note_id)) if @tag
    notes = notes.where(updated_at: @updated_after..) if @updated_after
    notes = notes.where(updated_at: ...@updated_before) if @updated_before
    notes
  end

  def candidates
    Passage.where(note_id: notes.select(:id))
  end

  def keyword_matches
    return [] unless (match = fts_query)

    candidates
      .joins("JOIN passages_search_index ON passages_search_index.rowid = passages.id")
      .where("passages_search_index MATCH ?", match)
      .order(Arel.sql("bm25(passages_search_index)"))
      .limit(CANDIDATES)
      .pluck(:id)
  end

  # The query as a bag of words, each quoted so that nothing a user types can
  # be read as FTS5 syntax.
  def fts_query
    words = @query.downcase.scan(/[\p{L}\p{N}]+/).uniq
    content = words.reject { |word| STOPWORDS.include?(word) }
    words = content if content.any?
    words.first(32).map { |word| %("#{word}") }.join(" OR ").presence
  end

  # [[passage_id, cosine_distance], ...] best first, and the ranking used. If
  # the query cannot be embedded, results fall back to keyword matches only.
  def semantic_matches
    vector = self.class.embedder.embed_query(@query)
    matches = candidates
      .where(embedding_model: self.class.embedder.model_key)
      .order(Arel.sql("distance"))
      .limit(CANDIDATES)
      .pluck(:id, Arel.sql(Passage.sanitize_sql_array([ "vec_distance_cosine(embedding, ?) AS distance", vector.to_json ])))
    [ matches, "hybrid" ]
  rescue StandardError => e
    Rails.logger.error("Retrieval: could not embed query, falling back to keyword ranking: #{e.class}: #{e.message}")
    [ [], "keyword" ]
  end

  def best(scores)
    passages = Passage.where(id: scores.keys).includes(note: :tags).index_by(&:id)
    per_note = Hash.new(0)

    scores.sort_by { |id, score| [ -score, id ] }.filter_map { |id, _| passages[id] }
      .select { |passage| (per_note[passage.note_id] += 1) <= MAX_PER_NOTE }
      .first(@limit)
  end
end
