# Cuts a note's current content into Passages. Splits along markdown headings,
# then paragraphs, packing consecutive paragraphs of one section into Passages
# of up to MAX_LENGTH characters. A paragraph that is too long on its own is
# split by lines, then sentences, then words. Checklist notes are split by line
# instead of by paragraph.
class Passage::Cutter
  # Bump whenever these rules change: the retrieval sweep recuts every note
  # whose Passages were cut by an older version.
  VERSION = 1

  # About 350 tokens of English, well inside the embedding model's window.
  MAX_LENGTH = 1_500

  Cut = Data.define(:heading_trail, :body)

  HEADING = /\A {0,3}(#+)[ \t]+(.+?)(?:[ \t]+#+)?[ \t]*\z/
  FENCE = /\A {0,3}(```|~~~)/

  def initialize(title:, body:, checklist: false)
    @title = title.to_s.strip.presence
    @body = body.to_s.gsub("\r\n", "\n")
    @checklist = checklist
  end

  def cuts
    cuts = sections.flat_map do |heading_trail, lines|
      pieces(lines).map { |piece| Cut.new(heading_trail:, body: piece) }
    end
    cuts.presence || fallback
  end

  private

  # A note with nothing but a title (or only headings) still gets one Passage,
  # so it can be retrieved.
  def fallback
    text = @title || @body.strip.presence
    text ? fit(text).map { |piece| Cut.new(heading_trail: [], body: piece) } : []
  end

  # [[heading_trail, lines], ...] in note order, one entry per section.
  def sections
    sections = [ [ [], [] ] ]
    trail = []
    in_fence = false

    @body.each_line(chomp: true) do |line|
      in_fence = !in_fence if line.match?(FENCE)

      if !in_fence && (heading = line.match(HEADING)) && heading[1].length <= 6
        level = heading[1].length
        trail = trail.take_while { |(other_level, _)| other_level < level } + [ [ level, heading[2].strip ] ]
        sections << [ trail.map(&:last), [] ]
      else
        sections.last.last << line
      end
    end

    sections
  end

  def pieces(lines)
    if @checklist
      pack(lines.reject(&:blank?).flat_map { |line| fit(line.strip) }, "\n")
    else
      pack(paragraphs(lines).flat_map { |paragraph| fit(paragraph) }, "\n\n")
    end
  end

  # Groups lines into paragraphs separated by blank lines. A fenced code block
  # stays one paragraph even when it contains blank lines.
  def paragraphs(lines)
    paragraphs = [ [] ]
    in_fence = false

    lines.each do |line|
      in_fence = !in_fence if line.match?(FENCE)

      if line.blank? && !in_fence
        paragraphs << [] if paragraphs.last.any?
      else
        paragraphs.last << line
      end
    end

    paragraphs.reject(&:empty?).map { |paragraph| paragraph.join("\n").strip }.compact_blank
  end

  # Splits text into pieces of at most MAX_LENGTH, preferring line, then
  # sentence, then word boundaries.
  def fit(text)
    return [ text ] if text.length <= MAX_LENGTH

    lines = text.split("\n").compact_blank
    return pack(lines.flat_map { |line| fit(line) }, "\n") if lines.size > 1

    sentences = text.split(/(?<=[.!?])\s+/)
    return pack(sentences.flat_map { |sentence| fit(sentence) }, " ") if sentences.size > 1

    wrap(text)
  end

  def wrap(text)
    pieces = []
    rest = text
    while rest.length > MAX_LENGTH
      split_at = rest.rindex(/\s/, MAX_LENGTH) || MAX_LENGTH
      split_at = MAX_LENGTH if split_at.zero?
      pieces << rest[0...split_at].strip
      rest = rest[split_at..].strip
    end
    pieces << rest
    pieces.compact_blank
  end

  # Joins consecutive pieces while they fit in one Passage.
  def pack(pieces, separator)
    pieces.each_with_object([]) do |piece, packed|
      if packed.any? && packed.last.length + separator.length + piece.length <= MAX_LENGTH
        packed.last << separator << piece
      else
        packed << piece.dup
      end
    end
  end
end
