require "rails_helper"

RSpec.describe NoteTag, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:note) }
    it { is_expected.to belong_to(:tag) }
  end
end
