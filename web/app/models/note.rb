class Note < ApplicationRecord
  belongs_to :user

  has_many :note_tags, dependent: :destroy
  has_many :tags, through: :note_tags
  has_many :note_versions, dependent: :destroy
  has_many :shares, dependent: :destroy
  has_many :shared_users, through: :shares, source: :user
  has_many :passages, -> { order(:position) }, dependent: :delete_all
  has_many_attached :attachments

  validates :body, length: { maximum: ->(note) { note.max_size || 32_768 } }
  validates :max_size, numericality: { greater_than: 0 }
  validate :archived_notes_cannot_be_pinned

  scope :active, -> { where(trashed: false, archived: false) }
  scope :pinned, -> { where(pinned: true) }
  scope :archived, -> { where(archived: true, trashed: false) }
  scope :trashed, -> { where(trashed: true) }
  scope :stale_trash, -> { trashed.where(trashed_at: ..30.days.ago) }
  scope :ordered, -> { order(pinned: :desc, updated_at: :desc) }
  scope :needing_passages, -> {
    where(passages_version: nil).or(where.not(passages_version: Passage::Cutter::VERSION))
  }

  after_update :create_version, if: :saved_change_to_body?
  after_save :cut_passages!, if: -> { previously_new_record? || saved_change_to_title? || saved_change_to_body? }
  after_commit :embed_passages_later, if: -> { @passages_recut }

  def soft_delete!
    update!(trashed: true, trashed_at: Time.current, pinned: false)
  end

  def restore!
    update!(trashed: false, trashed_at: nil)
  end

  def archive!
    update!(archived: true, pinned: false)
  end

  def unarchive!
    update!(archived: false)
  end

  def toggle_pin!
    return if archived? && !pinned?

    update!(pinned: !pinned)
  end

  def toggle_checklist!
    if checklist?
      update!(checklist: false)
    else
      convert_body_to_checklist!
      update!(checklist: true)
    end
  end

  def toggle_checklist_item!(line_index)
    return unless checklist? && body.present?

    lines = body.lines(chomp: true)
    return unless line_index >= 0 && line_index < lines.length

    line = lines[line_index]
    lines[line_index] = if line.match?(/^\s*- \[x\]/i)
      line.sub(/- \[x\]/i, "- [ ]")
    elsif line.match?(/^\s*- \[ \]/)
      line.sub("- [ ]", "- [x]")
    else
      line
    end

    update!(body: lines.join("\n"))
  end

  def duplicate!(new_owner: user)
    new_note = dup
    new_note.user = new_owner
    new_note.pinned = false
    new_note.archived = false
    new_note.trashed = false
    new_note.trashed_at = nil
    new_note.title = title.present? ? "#{title} (copy)" : nil
    new_note.save!
    tags.each { |tag| new_note.tags << tag rescue nil }
    new_note
  end

  def merge_with!(other_note)
    self.body = [ body, other_note.body ].compact.join("\n\n---\n\n")
    other_note.tags.each { |tag| tags << tag unless tags.include?(tag) }
    save!
  end

  def to_markdown
    content = ""
    content += "# #{title}\n\n" if title.present?
    content += body.to_s
    content
  end

  def self.search(query)
    return none if query.blank?
    where("id IN (SELECT rowid FROM notes_search_index WHERE notes_search_index MATCH ?)", query)
      .order(updated_at: :desc)
  end

  def accessible_by?(check_user)
    user_id == check_user.id || shares.exists?(user_id: check_user.id)
  end

  def editable_by?(check_user)
    user_id == check_user.id || shares.exists?(user_id: check_user.id, permission: :read_write)
  end

  # Replaces this note's Passages with ones cut from its current title and
  # body. Passages whose embedding input is unchanged keep their embedding;
  # the rest are embedded later by EmbedPassagesJob.
  def cut_passages!
    transaction do
      previous = Passage.where(note_id: id).where.not(embedding: nil)
        .pluck(:digest, :embedding, :embedding_model)
        .to_h { |digest, embedding, model| [ digest, [ embedding, model ] ] }
      Passage.where(note_id: id).delete_all

      rows = Passage::Cutter.new(title:, body:, checklist: checklist?).cuts.each_with_index.map do |cut, position|
        digest = Passage.digest_for(title:, heading_trail: cut.heading_trail, body: cut.body)
        embedding, embedding_model = previous[digest]
        { note_id: id, position:, title:, heading_trail: cut.heading_trail, body: cut.body, digest:, embedding:, embedding_model: }
      end
      Passage.insert_all!(rows) if rows.any?
      update_column(:passages_version, Passage::Cutter::VERSION)
    end
    passages.reset
    @passages_recut = true
  end

  private

  def archived_notes_cannot_be_pinned
    errors.add(:pinned, "cannot be true for archived notes") if archived? && pinned?
  end

  def embed_passages_later
    @passages_recut = false
    EmbedPassagesJob.perform_later
  end

  def create_version
    next_version = note_versions.maximum(:version_number).to_i + 1
    note_versions.create!(
      title: title_before_last_save,
      body: body_before_last_save,
      version_number: next_version,
      metadata: { changed_at: Time.current }.to_json
    )
  end

  def convert_body_to_checklist!
    return if body.blank?

    lines = body.lines(chomp: true)
    converted = lines.map do |line|
      if line.match?(/^\s*- \[[ x]\]/i)
        line
      elsif line.strip.empty?
        line
      else
        "- [ ] #{line.sub(/^\s*[-*]\s*/, '')}"
      end
    end
    self.body = converted.join("\n")
  end
end
