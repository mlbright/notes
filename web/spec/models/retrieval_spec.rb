require "rails_helper"

RSpec.describe Retrieval, type: :model do
  let(:user) { create(:user) }

  def note(**attributes)
    create(:note, user:, **attributes)
  end

  def retrieve(query, **options)
    EmbedPassagesJob.perform_now
    Retrieval.new(user:, query:, **options).call
  end

  def titles(result)
    result.passages.map { |passage| passage.note.title }
  end

  describe "ranking" do
    it "finds Passages by meaning when they share no words with the query" do
      note(title: "Car insurance renewal", body: "Premium went up; renews on 3 March.")
      note(title: "Sourdough", body: "Feed the starter the night before.")

      result = retrieve("auto policy")

      expect(result.ranking).to eq("hybrid")
      expect(titles(result)).to eq([ "Car insurance renewal" ])
    end

    it "finds Passages by wording" do
      note(title: "Router", body: "The admin page is 192.168.1.1 on channel 36.")
      note(title: "Sourdough", body: "Feed the starter the night before.")

      expect(titles(retrieve("channel"))).to eq([ "Router" ])
    end

    it "ranks a Passage matching by both wording and meaning first" do
      note(title: "Vehicle", body: "Tyres rotated in May.")
      note(title: "Car", body: "Oil change every 10,000 km.")

      expect(titles(retrieve("car oil")).first).to eq("Car")
    end

    it "drops weak semantic-only matches" do
      note(title: "Sourdough", body: "Feed the starter the night before.")

      expect(retrieve("kubernetes upgrade").passages).to be_empty
    end

    it "keeps keyword matches however weak their meaning" do
      note(title: "Sourdough", body: "Feed the starter the night before.")

      expect(titles(retrieve("starter motor"))).to eq([ "Sourdough" ])
    end

    it "returns Passages that are not embedded yet by wording alone" do
      note(title: "Router", body: "Channel 36 works best upstairs.")

      result = Retrieval.new(user:, query: "auto channel").call
      expect(titles(result)).to eq([ "Router" ])
    end

    it "ignores embeddings from another model" do
      note(title: "Car insurance renewal", body: "Premium went up.")
      EmbedPassagesJob.perform_now
      Passage.update_all(embedding_model: "old-model")

      expect(Retrieval.new(user:, query: "auto policy").call.passages).to be_empty
    end

    it "treats the query as plain words, never as search syntax" do
      note(title: "Router", body: "Channel 36.")

      expect { retrieve(%q{channel AND "36 OR (NOT* :x ^ -y}) }.not_to raise_error
      expect(retrieve("??? ---").passages).to be_empty
    end

    it "matches on stopwords only when the query has nothing else" do
      note(title: "Router", body: "Where is the admin page?")
      note(title: "Garden", body: "The tomatoes need water.")

      expect(titles(retrieve("where is the router"))).to eq([ "Router" ])
    end

    it "falls back to keyword ranking when the query cannot be embedded" do
      note(title: "Router", body: "Channel 36.")
      EmbedPassagesJob.perform_now
      Retrieval.embedder = StandInEmbedder.new(failing: true)

      result = Retrieval.new(user:, query: "channel").call
      expect(result.ranking).to eq("keyword")
      expect(titles(result)).to eq([ "Router" ])
    end
  end

  describe "limits" do
    it "returns at most 3 Passages per note" do
      note(title: "Car", body: (1..5).map { |i| "# Part #{i}\n\nThe car part #{i}." }.join("\n\n"))
      note(title: "Vehicle log", body: "Car washed.")

      result = retrieve("car")
      counts = result.passages.map(&:note_id).tally
      expect(counts.values.max).to eq(3)
      expect(counts.size).to eq(2)
    end

    it "returns the requested number of Passages, up to 50" do
      12.times { |i| note(title: "Car #{i}", body: "Car notes.") }

      expect(retrieve("car").passages.size).to eq(Retrieval::DEFAULT_LIMIT)
      expect(retrieve("car", limit: 2).passages.size).to eq(2)
      expect(Retrieval.new(user:, query: "car", limit: 500).instance_variable_get(:@limit)).to eq(Retrieval::MAX_LIMIT)
    end
  end

  describe "which notes are searched" do
    it "covers owned and shared notes, but not other users' or trashed notes" do
      other = create(:user)
      note(title: "Mine", body: "Car.")
      shared = create(:note, user: other, title: "Shared", body: "Car.")
      create(:share, note: shared, user:)
      create(:note, user: other, title: "Not shared", body: "Car.")
      note(title: "Trashed", body: "Car.", trashed: true, trashed_at: Time.current)

      expect(titles(retrieve("car"))).to contain_exactly("Mine", "Shared")
    end

    it "stops returning a note as soon as it is unshared" do
      shared = create(:note, user: create(:user), title: "Shared", body: "Car.")
      share = create(:share, note: shared, user:)
      EmbedPassagesJob.perform_now
      share.destroy!

      expect(Retrieval.new(user:, query: "car").call.passages).to be_empty
    end

    it "includes archived notes unless asked otherwise" do
      note(title: "Active", body: "Car.")
      note(title: "Archived", body: "Car.", archived: true)

      expect(titles(retrieve("car"))).to contain_exactly("Active", "Archived")
      expect(titles(retrieve("car", archived: "exclude"))).to eq([ "Active" ])
      expect(titles(retrieve("car", archived: "only"))).to eq([ "Archived" ])
    end

    it "filters by tag name, and an unknown tag matches nothing" do
      tagged = note(title: "Tagged", body: "Car.")
      note(title: "Untagged", body: "Car.")
      tagged.tags << create(:tag, user:, name: "vehicles")

      expect(titles(retrieve("car", tag: " Vehicles "))).to eq([ "Tagged" ])
      expect(retrieve("car", tag: "nope").passages).to be_empty
    end

    it "filters by when the note was last updated" do
      note(title: "Old", body: "Car.", updated_at: Time.zone.parse("2026-01-10"))
      note(title: "New", body: "Car.", updated_at: Time.zone.parse("2026-03-10"))

      expect(titles(retrieve("car", updated_after: Time.zone.parse("2026-02-01")))).to eq([ "New" ])
      expect(titles(retrieve("car", updated_before: Time.zone.parse("2026-02-01")))).to eq([ "Old" ])
    end
  end

  describe ".status" do
    it "counts the non-trashed notes whose Passages are all embedded" do
      note(title: "Car", body: "Car.")
      note(title: "Trashed", body: "Car.", trashed: true, trashed_at: Time.current)
      EmbedPassagesJob.perform_now
      note(title: "Pending", body: "Car.")

      status = Retrieval.status
      expect([ status.notes_embedded, status.notes_total ]).to eq([ 1, 2 ])
      expect(status.model).to eq("stand-in")
    end
  end
end
