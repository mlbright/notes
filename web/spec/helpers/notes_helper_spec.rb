require "rails_helper"

RSpec.describe NotesHelper, type: :helper do
  describe "#render_markdown" do
    it "renders markdown" do
      expect(helper.render_markdown("# Title\n\n**bold**")).to include("<h1>Title</h1>", "<strong>bold</strong>")
    end

    it "shows raw HTML as text instead of rendering it" do
      html = helper.render_markdown("ssh <host> then <script>alert(1)</script>")

      expect(html).to include("ssh &lt;host&gt;")
      expect(html).not_to include("<script")
    end

    it "does not turn javascript: links into links" do
      expect(helper.render_markdown("[click](javascript:alert(1))")).not_to include("href=\"javascript:")
    end

    it "opens safe links in a new tab" do
      expect(helper.render_markdown("[site](https://example.com)"))
        .to include('<a href="https://example.com" target="_blank" rel="noopener">site</a>')
    end
  end
end
