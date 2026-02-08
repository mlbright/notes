class Tag < ApplicationRecord
  belongs_to :user

  has_many :note_tags, dependent: :destroy
  has_many :notes, through: :note_tags

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, allow_blank: true }

  before_validation :normalize_name

  scope :ordered, -> { order(:name) }

  private

  def normalize_name
    self.name = name&.strip&.downcase
  end
end
