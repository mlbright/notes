require "rails_helper"

RSpec.describe Note, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:note_tags).dependent(:destroy) }
    it { is_expected.to have_many(:tags).through(:note_tags) }
    it { is_expected.to have_many(:note_versions).dependent(:destroy) }
    it { is_expected.to have_many(:shares).dependent(:destroy) }
    it { is_expected.to have_many(:shared_users).through(:shares) }
  end

  describe "validations" do
    it { is_expected.to validate_numericality_of(:max_size).is_greater_than(0) }
  end

  describe "scopes" do
    let(:user) { create(:user) }

    it ".active returns non-trashed, non-archived notes" do
      active = create(:note, user: user)
      create(:note, :trashed, user: user)
      create(:note, :archived, user: user)
      expect(Note.active).to eq([ active ])
    end

    it ".pinned returns only pinned notes" do
      create(:note, user: user)
      pinned = create(:note, :pinned, user: user)
      expect(Note.pinned).to eq([ pinned ])
    end

    it ".trashed returns only trashed notes" do
      create(:note, user: user)
      trashed = create(:note, :trashed, user: user)
      expect(Note.trashed).to eq([ trashed ])
    end

    it ".stale_trash returns notes trashed over 30 days ago" do
      create(:note, :trashed, user: user)
      stale = create(:note, :stale_trashed, user: user)
      expect(Note.stale_trash).to eq([ stale ])
    end
  end

  describe "#soft_delete!" do
    it "marks note as trashed with timestamp" do
      note = create(:note, pinned: true)
      note.soft_delete!
      expect(note.trashed?).to be true
      expect(note.trashed_at).to be_present
      expect(note.pinned?).to be false
    end
  end

  describe "#restore!" do
    it "removes trashed state" do
      note = create(:note, :trashed)
      note.restore!
      expect(note.trashed?).to be false
      expect(note.trashed_at).to be_nil
    end
  end

  describe "#archive!" do
    it "marks note as archived and unpins" do
      note = create(:note, :pinned)
      note.archive!
      expect(note.archived?).to be true
      expect(note.pinned?).to be false
    end
  end

  describe "#toggle_pin!" do
    it "toggles pinned state" do
      note = create(:note, pinned: false)
      note.toggle_pin!
      expect(note.pinned?).to be true
      note.toggle_pin!
      expect(note.pinned?).to be false
    end
  end

  describe "#duplicate!" do
    it "creates a copy of the note" do
      user = create(:user)
      tag = create(:tag, user: user)
      note = create(:note, user: user, title: "Original", body: "Content")
      note.tags << tag

      copy = note.duplicate!
      expect(copy).to be_persisted
      expect(copy.title).to eq("Original (copy)")
      expect(copy.body).to eq("Content")
      expect(copy.tags).to include(tag)
      expect(copy.pinned?).to be false
    end
  end

  describe "#merge_with!" do
    it "merges body and tags from another note" do
      user = create(:user)
      tag1 = create(:tag, user: user)
      tag2 = create(:tag, user: user)
      note1 = create(:note, user: user, body: "First")
      note2 = create(:note, user: user, body: "Second")
      note1.tags << tag1
      note2.tags << tag2

      note1.merge_with!(note2)
      expect(note1.body).to include("First")
      expect(note1.body).to include("Second")
      expect(note1.tags).to include(tag1, tag2)
    end
  end

  describe "#to_markdown" do
    it "formats note as markdown with title" do
      note = build(:note, title: "My Note", body: "Some content")
      md = note.to_markdown
      expect(md).to include("# My Note")
      expect(md).to include("Some content")
    end

    it "works without title" do
      note = build(:note, title: nil, body: "Just body")
      expect(note.to_markdown).to eq("Just body")
    end
  end

  describe "#accessible_by?" do
    let(:owner) { create(:user) }
    let(:other) { create(:user) }
    let(:note) { create(:note, user: owner) }

    it "returns true for the owner" do
      expect(note.accessible_by?(owner)).to be true
    end

    it "returns true for a shared user" do
      create(:share, note: note, user: other)
      expect(note.accessible_by?(other)).to be true
    end

    it "returns false for unrelated user" do
      expect(note.accessible_by?(other)).to be false
    end
  end

  describe "version history" do
    it "creates a version when body changes on persisted note" do
      note = create(:note, body: "original")
      note.update!(body: "updated")
      expect(note.note_versions.count).to eq(1)
      expect(note.note_versions.last.body).to eq("original")
    end

    it "does not create a version on initial save" do
      note = create(:note)
      expect(note.note_versions.count).to eq(0)
    end
  end
end
