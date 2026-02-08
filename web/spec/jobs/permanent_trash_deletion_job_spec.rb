require "rails_helper"

RSpec.describe PermanentTrashDeletionJob, type: :job do
  let(:user) { create(:user) }

  it "deletes notes trashed over 30 days ago" do
    stale = create(:note, :stale_trashed, user: user)
    recent = create(:note, :trashed, user: user)
    active = create(:note, user: user)

    PermanentTrashDeletionJob.perform_now

    expect(Note.exists?(stale.id)).to be false
    expect(Note.exists?(recent.id)).to be true
    expect(Note.exists?(active.id)).to be true
  end
end
