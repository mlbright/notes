class User < ApplicationRecord
  has_secure_password validations: false

  enum :role, { user: 0, admin: 1 }

  has_many :notes, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :shares, dependent: :destroy
  has_many :shared_notes, through: :shares, source: :note

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :uid, uniqueness: true, allow_nil: true
  validates :session_timeout, numericality: { greater_than: 0 }
  validates :password, length: { minimum: 4 }, allow_nil: true
  validate :must_have_auth_method

  before_validation :set_defaults, on: :create

  def self.from_omniauth(auth)
    find_or_initialize_by(uid: auth.uid, provider: auth.provider).tap do |user|
      user.name = auth.info.name
      user.email = auth.info.email
      user.save!
    end
  end

  def self.authenticate_by_password(email, password)
    user = find_by(email: email)
    return nil unless user&.password_digest.present?
    user.authenticate(password) || nil
  end

  def oauth_user?
    uid.present? && provider.present?
  end

  def password_user?
    password_digest.present?
  end

  before_validation :set_defaults, on: :create

  def self.from_omniauth(auth)
    find_or_initialize_by(uid: auth.uid, provider: auth.provider).tap do |user|
      user.name = auth.info.name
      user.email = auth.info.email
      user.save!
    end
  end

  def generate_api_token!
    update!(api_token: SecureRandom.hex(32), token_expires_at: 30.days.from_now)
    api_token
  end

  def refresh_api_token!
    return generate_api_token! if token_expired?
    update!(token_expires_at: 30.days.from_now)
    api_token
  end

  def token_expired?
    token_expires_at.nil? || token_expires_at < Time.current
  end

  def accessible_notes
    Note.where(id: notes.select(:id)).or(Note.where(id: shared_notes.select(:id)))
  end

  private

  def set_defaults
    self.role ||= :user
    self.session_timeout ||= 3600
  end

  def must_have_auth_method
    unless oauth_user? || password_digest.present?
      errors.add(:base, "Must have either OAuth credentials or a password")
    end
  end
end
