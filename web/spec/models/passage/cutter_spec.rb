require "rails_helper"

RSpec.describe Passage::Cutter do
  def cuts(body, title: "Title", checklist: false)
    described_class.new(title:, body:, checklist:).cuts.map { |cut| [ cut.heading_trail, cut.body ] }
  end

  it "keeps a short note in one Passage" do
    expect(cuts("First paragraph.\n\nSecond paragraph.")).to eq([ [ [], "First paragraph.\n\nSecond paragraph." ] ])
  end

  it "splits along headings and records each Passage's Heading Trail" do
    body = <<~MD
      Intro.

      # Backups

      Overview.

      ## S3 bucket

      Versioned.

      ## Restore

      Run the script.

      # Other

      Misc.
    MD

    expect(cuts(body)).to eq([
      [ [], "Intro." ],
      [ [ "Backups" ], "Overview." ],
      [ [ "Backups", "S3 bucket" ], "Versioned." ],
      [ [ "Backups", "Restore" ], "Run the script." ],
      [ [ "Other" ], "Misc." ]
    ])
  end

  it "keeps the enclosing headings when a level is skipped" do
    expect(cuts("# A\n\n### C\n\nText.")).to eq([ [ [ "A", "C" ], "Text." ] ])
  end

  it "strips closing hashes and ignores hashtags" do
    expect(cuts("## Plans ##\n\n#todo buy milk")).to eq([ [ [ "Plans" ], "#todo buy milk" ] ])
  end

  it "skips sections with no content" do
    expect(cuts("# Empty\n\n# Full\n\nText.")).to eq([ [ [ "Full" ], "Text." ] ])
  end

  it "does not treat # lines inside code fences as headings" do
    body = "# Setup\n\n```sh\n# install\n\nbundle install\n```"
    expect(cuts(body)).to eq([ [ [ "Setup" ], "```sh\n# install\n\nbundle install\n```" ] ])
  end

  it "packs paragraphs into Passages of at most MAX_LENGTH characters" do
    paragraph = "word " * 80 # 399 characters once stripped, so three fit
    body = Array.new(7) { paragraph.strip }.join("\n\n")

    bodies = cuts(body).map(&:last)
    expect(bodies.size).to eq(3)
    expect(bodies.map(&:length)).to all(be <= described_class::MAX_LENGTH)
    expect(bodies.first.split("\n\n").size).to eq(3)
  end

  it "splits a paragraph that is too long by sentences" do
    sentence = "#{'lorem ' * 40}end."
    paragraph = Array.new(10) { sentence }.join(" ")

    bodies = cuts(paragraph).map(&:last)
    expect(bodies.size).to be > 1
    expect(bodies.map(&:length)).to all(be <= described_class::MAX_LENGTH)
    expect(bodies).to all(end_with("end."))
  end

  it "splits a long list paragraph by lines" do
    list = Array.new(60) { |i| "- item number #{i} with some words after it" }.join("\n")

    bodies = cuts(list).map(&:last)
    expect(bodies.size).to be > 1
    expect(bodies.map(&:length)).to all(be <= described_class::MAX_LENGTH)
    expect(bodies.flat_map { |body| body.split("\n") }.size).to eq(60)
  end

  it "wraps a single run of text with no sentence breaks" do
    bodies = cuts("x" * 4_000).map(&:last)
    expect(bodies.map(&:length)).to eq([ 1_500, 1_500, 1_000 ])
  end

  it "splits checklist notes by line" do
    body = "- [ ] milk\n\n- [x] eggs\n- [ ] bread"
    expect(cuts(body, checklist: true)).to eq([ [ [], "- [ ] milk\n- [x] eggs\n- [ ] bread" ] ])
  end

  it "makes a title-only note one Passage whose text is the title" do
    expect(cuts("", title: "Call the plumber")).to eq([ [ [], "Call the plumber" ] ])
    expect(cuts(nil, title: "Call the plumber")).to eq([ [ [], "Call the plumber" ] ])
  end

  it "falls back to the title when the body has only headings" do
    expect(cuts("# Shopping", title: "List")).to eq([ [ [], "List" ] ])
  end

  it "cuts nothing from an empty note" do
    expect(cuts("  \n", title: nil)).to eq([])
  end

  it "normalises Windows line endings" do
    expect(cuts("# A\r\n\r\nText.\r\n")).to eq([ [ [ "A" ], "Text." ] ])
  end
end
