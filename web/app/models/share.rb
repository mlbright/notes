class Share < ApplicationRecord
  belongs_to :note
  belongs_to :user

  enum :permission, { read_write: 0 }

  validates :user_id, uniqueness: { scope: :note_id, message: "already has access to this note" }
  validate :cannot_share_with_owner

  private

  def cannot_share_with_owner
    errors.add(:user, "cannot share a note with its owner") if note && user_id == note.user_id
  end
end
