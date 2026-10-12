require "rails_helper"

RSpec.describe RetrievalSweepJob, type: :job do
  it "recuts notes cut by older rules or never cut" do
    old = create(:note, body: "Old rules.")
    old.update_column(:passages_version, Passage::Cutter::VERSION - 1)
    never = create(:note, body: "Never cut.")
    never.update_column(:passages_version, nil)
    Passage.delete_all

    RetrievalSweepJob.perform_now

    expect(old.passages.pluck(:body)).to eq([ "Old rules." ])
    expect(never.passages.pluck(:body)).to eq([ "Never cut." ])
    expect([ old.reload, never.reload ].map(&:passages_version)).to all(eq(Passage::Cutter::VERSION))
  end

  it "queues embedding when any Passage still needs it" do
    create(:note, body: "Text.")
    expect { RetrievalSweepJob.perform_now }.to have_enqueued_job(EmbedPassagesJob)

    EmbedPassagesJob.perform_now
    expect { RetrievalSweepJob.perform_now }.not_to have_enqueued_job(EmbedPassagesJob)
  end

  it "records when it last ran" do
    allow(Rails.cache).to receive(:write)
    RetrievalSweepJob.perform_now
    expect(Rails.cache).to have_received(:write).with(RetrievalSweepJob::LAST_RUN_KEY, kind_of(Time))
  end
end
