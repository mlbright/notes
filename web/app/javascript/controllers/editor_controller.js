import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["markdownEditor", "charCount"]

  connect() {
    this.updateCharCount(this.markdownEditorTarget.value || "")
    this.markdownEditorTarget.addEventListener("input", this.onInput)
  }

  onInput = () => {
    this.updateCharCount(this.markdownEditorTarget.value)
  }

  updateCharCount(text) {
    if (this.hasCharCountTarget) {
      this.charCountTarget.textContent = (text || "").length
    }
  }

  disconnect() {
    this.markdownEditorTarget.removeEventListener("input", this.onInput)
  }
}
