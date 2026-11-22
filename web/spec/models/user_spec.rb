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

    it "requires a password" do
      user = build(:user, password: nil, password_confirmation: nil)
      expect(user).not_to be_valid
      expect(user.errors[:base]).to include("Must have a password")
    end

    it "does not accept a Google identity in place of a password" do
      user = build(:user, :legacy_google_identity, password: nil, password_confirmation: nil)
      expect(user).not_to be_valid
    end

    it "accepts a user with a password" do
      expect(build(:user)).to be_valid
    end

    it "validates password length when set" do
      user = build(:user, password: "abc")
      expect(user).not_to be_valid
    end
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:role).with_values(user: 0, admin: 1) }
  end

  describe ".authenticate_by_password" do
    let!(:user) { create(:user, email: "pw@example.com", password: "secret1234") }

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

  describe ".authenticate_by_api_token" do
    let!(:user) { create(:user) }

    it "returns the user for a valid token" do
      token = user.generate_api_token!
      expect(User.authenticate_by_api_token(token)).to eq(user)
    end

    it "returns nil for an expired token" do
      user.update!(api_token: "test", token_expires_at: 1.day.ago)
      expect(User.authenticate_by_api_token("test")).to be_nil
    end

    it "returns nil for a blank token even when a user has no token" do
      expect(User.authenticate_by_api_token(nil)).to be_nil
      expect(User.authenticate_by_api_token("")).to be_nil
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
