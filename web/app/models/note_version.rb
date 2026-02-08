class NoteVersion < ApplicationRecord
  belongs_to :note

  validates :version_number, presence: true, uniqueness: { scope: :note_id }

  scope :ordered, -> { order(version_number: :desc) }

  def diff_from_current
    {
      title: { was: title, now: note.title },
      body: { was: body, now: note.body }
    }
  end
end
