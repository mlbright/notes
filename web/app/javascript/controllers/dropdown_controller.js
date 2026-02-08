import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this.clickOutside = this.clickOutside.bind(this)
    document.addEventListener("click", this.clickOutside)
  }

  disconnect() {
    document.removeEventListener("click", this.clickOutside)
  }

  toggle(event) {
    event.stopPropagation()
    this.menuTarget.classList.toggle("hidden")
  }

  clickOutside() {
    this.menuTarget.classList.add("hidden")
  }
}
