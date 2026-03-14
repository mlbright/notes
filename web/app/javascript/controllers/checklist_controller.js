import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggle(event) {
    const checkbox = event.currentTarget
    const url = checkbox.dataset.checklistUrl
    const token = document.querySelector('meta[name="csrf-token"]')?.content

    fetch(url, {
      method: "PATCH",
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": token
      }
    }).then(response => {
      if (response.ok) {
        return response.text()
      }
    }).then(html => {
      if (html) {
        Turbo.renderStreamMessage(html)
      }
    })
  }
}
