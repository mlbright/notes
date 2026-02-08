module NotesHelper
  def render_markdown(text)
    return "" if text.blank?
    renderer = Redcarpet::Render::HTML.new(hard_wrap: true, link_attributes: { target: "_blank", rel: "noopener" })
    markdown = Redcarpet::Markdown.new(renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      highlight: true,
      no_intra_emphasis: true
    )
    markdown.render(text).html_safe
  end
end
