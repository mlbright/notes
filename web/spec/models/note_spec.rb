require "rails_helper"

RSpec.describe Note, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:note_tags).dependent(:destroy) }
    it { is_expected.to have_many(:tags).through(:note_tags) }
    it { is_expected.to have_many(:note_versions).dependent(:destroy) }
    it { is_expected.to have_many(:shares).dependent(:destroy) }
    it { is_expected.to have_many(:shared_users).through(:shares) }
    it { is_expected.to have_many(:passages).dependent(:delete_all) }
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

    it "does not pin an archived note" do
      note = create(:note, :archived)
      note.toggle_pin!
      expect(note.pinned?).to be false
    end
  end

  describe "validation" do
    it "prevents archived notes from being pinned" do
      note = build(:note, archived: true, pinned: true)
      expect(note).not_to be_valid
      expect(note.errors[:pinned]).to include("cannot be true for archived notes")
    end
  end

  describe "#toggle_checklist!" do
    it "enables checklist mode and converts body lines to checklist items" do
      note = create(:note, body: "Buy milk\nClean house")
      note.toggle_checklist!
      expect(note.checklist?).to be true
      expect(note.body).to include("- [ ] Buy milk")
      expect(note.body).to include("- [ ] Clean house")
    end

    it "disables checklist mode without modifying body" do
      note = create(:note, :checklist)
      original_body = note.body
      note.toggle_checklist!
      expect(note.checklist?).to be false
      expect(note.body).to eq(original_body)
    end

    it "preserves existing checklist markers when enabling" do
      note = create(:note, body: "- [x] Done item\n- [ ] Todo item\nPlain line")
      note.toggle_checklist!
      expect(note.body).to include("- [x] Done item")
      expect(note.body).to include("- [ ] Todo item")
      expect(note.body).to include("- [ ] Plain line")
    end

    it "strips existing bullet markers when converting" do
      note = create(:note, body: "- Buy milk\n* Clean house")
      note.toggle_checklist!
      expect(note.body).to include("- [ ] Buy milk")
      expect(note.body).to include("- [ ] Clean house")
    end
  end

  describe "#toggle_checklist_item!" do
    it "checks an unchecked item" do
      note = create(:note, :checklist)
      note.toggle_checklist_item!(0)
      expect(note.body.lines(chomp: true)[0]).to match(/- \[x\] Buy groceries/)
    end

    it "unchecks a checked item" do
      note = create(:note, :checklist)
      note.toggle_checklist_item!(2)
      expect(note.body.lines(chomp: true)[2]).to match(/- \[ \] Send email/)
    end

    it "does nothing for out-of-range index" do
      note = create(:note, :checklist)
      original_body = note.body
      note.toggle_checklist_item!(99)
      expect(note.body).to eq(original_body)
    end

    it "does nothing when checklist mode is off" do
      note = create(:note, body: "- [ ] Item")
      original_body = note.body
      note.toggle_checklist_item!(0)
      expect(note.body).to eq(original_body)
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

  describe ".search" do
    let(:user) { create(:user) }

    it "matches notes containing every term" do
      both = create(:note, user: user, body: "ssh port forwarding")
      create(:note, user: user, body: "ssh keys")

      expect(Note.search("ssh forwarding")).to eq([ both ])
    end

    it "reads nothing the user types as FTS5 syntax" do
      note = create(:note, user: user, title: "Tunnels", body: %(Run "ssh -N -L 8443:localhost:443 host" for NOT title: forwarding))

      [ "ssh -L", "title:tunnels", "NOT forwarding", %(unbalanced "quote), "8443:localhost:443", "ssh*", "(ssh", "-" ].each do |query|
        expect { Note.search(query).to_a }.not_to raise_error, query
      end
      expect(Note.search("ssh -L")).to eq([ note ])
      expect(Note.search("NOT forwarding")).to eq([ note ])
    end

    it "matches nothing for a blank query" do
      create(:note, user: user, body: "anything")

      expect(Note.search("  ")).to be_empty
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

  describe "passages" do
    let(:note) { create(:note, title: "Backups", body: "# S3\n\nVersioned bucket.\n\n# Restore\n\nRun the script.") }

    it "cuts Passages when the note is created" do
      expect(note.passages.map { |passage| [ passage.heading_trail, passage.body ] }).to eq([
        [ [ "S3" ], "Versioned bucket." ],
        [ [ "Restore" ], "Run the script." ]
      ])
      expect(note.passages_version).to eq(Passage::Cutter::VERSION)
    end

    it "recuts them when the body changes" do
      note.update!(body: "Just one paragraph.")
      expect(note.passages.pluck(:body)).to eq([ "Just one paragraph." ])
    end

    it "recuts them when the title changes, since it is part of what is embedded" do
      note.update!(title: "Disaster recovery")
      expect(note.passages.pluck(:title).uniq).to eq([ "Disaster recovery" ])
    end

    it "leaves them alone when only the note's status changes" do
      ids = note.passages.ids
      note.archive!
      note.toggle_pin!
      expect(note.passages.reload.ids).to eq(ids)
    end

    it "keeps the embedding of a Passage whose text is unchanged" do
      note.passages.each do |passage|
        passage.update_columns(embedding: Passage.pack_embedding([ 1.0, 0.0 ]), embedding_model: "stand-in")
      end

      note.update!(body: "# S3\n\nVersioned bucket.\n\n# Restore\n\nRun the restore script.")

      expect(note.passages.map { |passage| [ passage.body, passage.embedding_model ] }).to eq([
        [ "Versioned bucket.", "stand-in" ],
        [ "Run the restore script.", nil ]
      ])
    end

    it "queues embedding after the change commits" do
      note
      expect { note.update!(body: "New text.") }.to have_enqueued_job(EmbedPassagesJob).exactly(:once)
      expect { note.archive! }.not_to have_enqueued_job(EmbedPassagesJob)
    end

    it "deletes them with the note" do
      note
      expect { note.destroy! }.to change(Passage, :count).to(0)
    end

    it ".needing_passages finds notes never cut or cut by older rules" do
      current = note
      old = create(:note)
      old.update_column(:passages_version, Passage::Cutter::VERSION - 1)
      never = create(:note)
      never.update_column(:passages_version, nil)

      expect(Note.needing_passages).to contain_exactly(old, never)
      expect(Note.needing_passages).not_to include(current)
    end
  end
end
