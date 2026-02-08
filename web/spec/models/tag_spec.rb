require "rails_helper"

RSpec.describe Tag, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:note_tags).dependent(:destroy) }
    it { is_expected.to have_many(:notes).through(:note_tags) }
  end

  describe "validations" do
    subject { build(:tag) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:user_id).case_insensitive }
  end

  describe "normalization" do
    it "downcases and strips tag names" do
      tag = create(:tag, name: "  My Tag  ")
      expect(tag.name).to eq("my tag")
    end
  end

  describe "color validation" do
    it "accepts valid hex colors" do
      tag = build(:tag, color: "#ff5733")
      expect(tag).to be_valid
    end

    it "rejects invalid color formats" do
      tag = build(:tag, color: "not-a-color")
      expect(tag).not_to be_valid
    end
  end
end
