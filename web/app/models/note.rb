class Note < ApplicationRecord
  belongs_to :user

  has_many :note_tags, dependent: :destroy
  has_many :tags, through: :note_tags
  has_many :note_versions, dependent: :destroy
  has_many :shares, dependent: :destroy
  has_many :shared_users, through: :shares, source: :user
  has_many_attached :attachments

  validates :body, length: { maximum: ->(note) { note.max_size || 32_768 } }
  validates :max_size, numericality: { greater_than: 0 }

  scope :active, -> { where(trashed: false, archived: false) }
  scope :pinned, -> { where(pinned: true) }
  scope :archived, -> { where(archived: true, trashed: false) }
  scope :trashed, -> { where(trashed: true) }
  scope :stale_trash, -> { trashed.where(trashed_at: ..30.days.ago) }
  scope :ordered, -> { order(pinned: :desc, updated_at: :desc) }

  after_update :create_version, if: :saved_change_to_body?

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
    update!(pinned: !pinned)
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
  end

  def accessible_by?(check_user)
    user_id == check_user.id || shares.exists?(user_id: check_user.id)
  end

  def editable_by?(check_user)
    user_id == check_user.id || shares.exists?(user_id: check_user.id, permission: :read_write)
  end

  private

  def create_version
    next_version = note_versions.maximum(:version_number).to_i + 1
    note_versions.create!(
      title: title_before_last_save,
      body: body_before_last_save,
      version_number: next_version,
      metadata: { changed_at: Time.current }.to_json
    )
  end
end
