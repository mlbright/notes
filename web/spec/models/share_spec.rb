require "rails_helper"

RSpec.describe Share, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:note) }
    it { is_expected.to belong_to(:user) }
  end

  describe "validations" do
    it "prevents duplicate shares" do
      user = create(:user)
      note = create(:note)
      create(:share, note: note, user: user)
      duplicate = build(:share, note: note, user: user)
      expect(duplicate).not_to be_valid
    end

    it "prevents sharing a note with its owner" do
      owner = create(:user)
      note = create(:note, user: owner)
      share = build(:share, note: note, user: owner)
      expect(share).not_to be_valid
      expect(share.errors[:user]).to include("cannot share a note with its owner")
    end
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:permission).with_values(read_write: 0) }
  end
end
