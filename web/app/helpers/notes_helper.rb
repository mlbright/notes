module NotesHelper
  # Note bodies are untrusted: a shared note is written by another user. Raw
  # HTML is shown as text (so placeholders like <host> stay visible) and only
  # safe link schemes become links.
  def render_markdown(text)
    return "" if text.blank?
    renderer = Redcarpet::Render::HTML.new(
      escape_html: true,
      safe_links_only: true,
      hard_wrap: true,
      link_attributes: { target: "_blank", rel: "noopener" }
    )
    markdown = Redcarpet::Markdown.new(renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      highlight: true,
      no_intra_emphasis: true,
      lax_spacing: true
    )
    markdown.render(text).html_safe
  end
end
