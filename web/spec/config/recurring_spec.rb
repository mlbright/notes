require "rails_helper"
require "fugit"

# config/recurring.yml is only read by Solid Queue in production, so a missing
# or malformed entry would otherwise go unnoticed until the job never runs.
# Schedules are parsed with Fugit, as Solid Queue does.
RSpec.describe "config/recurring.yml" do
  let(:tasks) { ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/recurring.yml")).fetch("production") }

  it "gives every production task a valid schedule and a job class or command" do
    tasks.each do |key, options|
      expect(Fugit.parse(options["schedule"])).to be_a(Fugit::Cron), "#{key}: unsupported schedule"
      if options["class"]
        expect(options["class"].safe_constantize).to be < ActiveJob::Base, "#{key}: unknown job class"
      else
        expect(options["command"]).to be_present, "#{key}: no class or command"
      end
    end
  end

  it "purges stale trash once a day" do
    _, options = tasks.find { |_, options| options["class"] == "PermanentTrashDeletionJob" }

    expect(options).to be_present
    cron = Fugit.parse(options["schedule"])
    expect([ cron.hours.size, cron.minutes.size, cron.weekdays, cron.monthdays ]).to eq([ 1, 1, nil, nil ])
  end
end
