import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["richEditor", "markdownEditor", "hiddenField", "modeToggle", "toolbar", "charCount"]

  connect() {
    this.mode = "rich" // "rich" or "markdown"
    this.initRichEditor()
  }

  async initRichEditor() {
    // Dynamic import of Tiptap — loaded via CDN/importmap
    try {
      const { Editor } = await import("@tiptap/core")
      const { default: StarterKit } = await import("@tiptap/starter-kit")
      const { default: Link } = await import("@tiptap/extension-link")
      const { Markdown } = await import("@tiptap/markdown")

      this.editor = new Editor({
        element: this.richEditorTarget,
        extensions: [
          StarterKit,
          Link.configure({ openOnClick: false }),
          Markdown
        ],
        content: this.markdownEditorTarget.value || "",
        onUpdate: ({ editor }) => {
          const markdown = editor.storage.markdown.getMarkdown()
          this.markdownEditorTarget.value = markdown
          this.hiddenFieldTarget.value = markdown
          this.updateCharCount(markdown)
        }
      })

      // Initialize hidden field
      this.hiddenFieldTarget.value = this.markdownEditorTarget.value
      this.updateCharCount(this.markdownEditorTarget.value || "")
    } catch (e) {
      // Fallback: if Tiptap can't load, show markdown editor
      console.warn("Tiptap not available, falling back to markdown editor", e)
      this.switchToMarkdown()
    }
  }

  toggleMode() {
    if (this.mode === "rich") {
      this.switchToMarkdown()
    } else {
      this.switchToRich()
    }
  }

  switchToMarkdown() {
    this.mode = "markdown"
    this.richEditorTarget.classList.add("hidden")
    this.markdownEditorTarget.classList.remove("hidden")
    this.toolbarTarget.classList.add("hidden")
    this.modeToggleTarget.textContent = "Switch to Rich Text"

    if (this.editor) {
      const markdown = this.editor.storage.markdown.getMarkdown()
      this.markdownEditorTarget.value = markdown
    }

    // Sync on markdown input
    this.markdownEditorTarget.addEventListener("input", () => {
      this.hiddenFieldTarget.value = this.markdownEditorTarget.value
      this.updateCharCount(this.markdownEditorTarget.value)
    })
  }

  switchToRich() {
    this.mode = "rich"
    this.richEditorTarget.classList.remove("hidden")
    this.markdownEditorTarget.classList.add("hidden")
    this.toolbarTarget.classList.remove("hidden")
    this.modeToggleTarget.textContent = "Switch to Markdown"

    if (this.editor) {
      this.editor.commands.setContent(this.markdownEditorTarget.value || "")
    }
  }

  // Toolbar actions
  bold() { this.editor?.chain().focus().toggleBold().run() }
  italic() { this.editor?.chain().focus().toggleItalic().run() }
  heading() { this.editor?.chain().focus().toggleHeading({ level: 2 }).run() }
  bulletList() { this.editor?.chain().focus().toggleBulletList().run() }
  orderedList() { this.editor?.chain().focus().toggleOrderedList().run() }
  codeBlock() { this.editor?.chain().focus().toggleCodeBlock().run() }
  blockquote() { this.editor?.chain().focus().toggleBlockquote().run() }

  link() {
    const url = prompt("Enter URL:")
    if (url) {
      this.editor?.chain().focus().setLink({ href: url }).run()
    }
  }

  updateCharCount(text) {
    if (this.hasCharCountTarget) {
      this.charCountTarget.textContent = (text || "").length
    }
  }

  disconnect() {
    this.editor?.destroy()
  }
}
