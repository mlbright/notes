require "rails_helper"

RSpec.describe NoteVersion, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:note) }
  end

  describe "validations" do
    subject { build(:note_version) }

    it { is_expected.to validate_presence_of(:version_number) }
    it { is_expected.to validate_uniqueness_of(:version_number).scoped_to(:note_id) }
  end

  describe "#diff_from_current" do
    it "returns diff between version and current note" do
      note = create(:note, title: "Current", body: "Current body")
      version = create(:note_version, note: note, title: "Old", body: "Old body", version_number: 1)

      diff = version.diff_from_current
      expect(diff[:title][:was]).to eq("Old")
      expect(diff[:title][:now]).to eq("Current")
      expect(diff[:body][:was]).to eq("Old body")
      expect(diff[:body][:now]).to eq("Current body")
    end
  end
end
