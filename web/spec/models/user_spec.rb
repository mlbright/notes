require "rails_helper"

RSpec.describe User, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:notes).dependent(:destroy) }
    it { is_expected.to have_many(:tags).dependent(:destroy) }
    it { is_expected.to have_many(:shares).dependent(:destroy) }
    it { is_expected.to have_many(:shared_notes).through(:shares) }
  end

  describe "validations" do
    subject { build(:user) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email) }
    it { is_expected.to validate_numericality_of(:session_timeout).is_greater_than(0) }

    it "requires either OAuth credentials or a password" do
      user = build(:user, uid: nil, provider: nil, password: nil)
      expect(user).not_to be_valid
      expect(user.errors[:base]).to include("Must have either OAuth credentials or a password")
    end

    it "accepts a user with only OAuth credentials" do
      user = build(:user)
      expect(user).to be_valid
    end

    it "accepts a user with only a password" do
      user = build(:user, :password_user)
      expect(user).to be_valid
    end

    it "validates password length when set" do
      user = build(:user, :password_user, password: "abc")
      expect(user).not_to be_valid
    end
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:role).with_values(user: 0, admin: 1) }
  end

  describe ".from_omniauth" do
    let(:auth) do
      OpenStruct.new(
        uid: "12345",
        provider: "google_oauth2",
        info: OpenStruct.new(name: "Test User", email: "test@example.com")
      )
    end

    it "creates a new user from OAuth data" do
      expect { User.from_omniauth(auth) }.to change(User, :count).by(1)
      user = User.last
      expect(user.name).to eq("Test User")
      expect(user.email).to eq("test@example.com")
      expect(user.uid).to eq("12345")
    end

    it "finds and updates an existing user" do
      existing = create(:user, uid: "12345", provider: "google_oauth2")
      expect { User.from_omniauth(auth) }.not_to change(User, :count)
      existing.reload
      expect(existing.name).to eq("Test User")
    end
  end

  describe ".authenticate_by_password" do
    let!(:user) { create(:user, :password_user, email: "pw@example.com", password: "secret1234") }

    it "returns the user for correct credentials" do
      result = User.authenticate_by_password("pw@example.com", "secret1234")
      expect(result).to eq(user)
    end

    it "returns nil for wrong password" do
      result = User.authenticate_by_password("pw@example.com", "wrong")
      expect(result).to be_nil
    end

    it "returns nil for nonexistent email" do
      result = User.authenticate_by_password("nobody@example.com", "secret1234")
      expect(result).to be_nil
    end

    it "returns nil for OAuth-only user" do
      oauth_user = create(:user)
      result = User.authenticate_by_password(oauth_user.email, "anything")
      expect(result).to be_nil
    end
  end

  describe "#oauth_user? and #password_user?" do
    it "identifies OAuth users" do
      user = build(:user)
      expect(user.oauth_user?).to be true
      expect(user.password_user?).to be false
    end

    it "identifies password users" do
      user = build(:user, :password_user)
      expect(user.oauth_user?).to be false
      expect(user.password_user?).to be true
    end
  end

  describe "#generate_api_token!" do
    let(:user) { create(:user) }

    it "generates a token and sets expiration" do
      token = user.generate_api_token!
      expect(token).to be_present
      expect(user.token_expires_at).to be > Time.current
    end
  end

  describe "#token_expired?" do
    let(:user) { create(:user) }

    it "returns true when no token exists" do
      expect(user.token_expired?).to be true
    end

    it "returns false for a valid token" do
      user.generate_api_token!
      expect(user.token_expired?).to be false
    end

    it "returns true for an expired token" do
      user.update!(api_token: "test", token_expires_at: 1.day.ago)
      expect(user.token_expired?).to be true
    end
  end

  describe "#accessible_notes" do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }

    it "includes owned notes" do
      note = create(:note, user: user)
      expect(user.accessible_notes).to include(note)
    end

    it "includes shared notes" do
      note = create(:note, user: other_user)
      create(:share, note: note, user: user)
      expect(user.accessible_notes).to include(note)
    end

    it "excludes other users' unshared notes" do
      note = create(:note, user: other_user)
      expect(user.accessible_notes).not_to include(note)
    end
  end
end
