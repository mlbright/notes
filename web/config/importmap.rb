# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Tiptap editor
pin "@tiptap/core", to: "https://cdn.jsdelivr.net/npm/@tiptap/core@2/+esm"
pin "@tiptap/starter-kit", to: "https://cdn.jsdelivr.net/npm/@tiptap/starter-kit@2/+esm"
pin "@tiptap/extension-link", to: "https://cdn.jsdelivr.net/npm/@tiptap/extension-link@2/+esm"
pin "@tiptap/markdown", to: "https://cdn.jsdelivr.net/npm/@tiptap/markdown@2/+esm"
pin "@tiptap/pm/state", to: "https://cdn.jsdelivr.net/npm/@tiptap/pm@2/state/+esm"
pin "@tiptap/pm/model", to: "https://cdn.jsdelivr.net/npm/@tiptap/pm@2/model/+esm"
pin "@tiptap/pm/view", to: "https://cdn.jsdelivr.net/npm/@tiptap/pm@2/view/+esm"
pin "@tiptap/pm/transform", to: "https://cdn.jsdelivr.net/npm/@tiptap/pm@2/transform/+esm"
pin "@tiptap/pm/commands", to: "https://cdn.jsdelivr.net/npm/@tiptap/pm@2/commands/+esm"
pin "@tiptap/pm/keymap", to: "https://cdn.jsdelivr.net/npm/@tiptap/pm@2/keymap/+esm"
pin "@tiptap/pm/schema-list", to: "https://cdn.jsdelivr.net/npm/@tiptap/pm@2/schema-list/+esm"
pin "@tiptap/pm/dropcursor", to: "https://cdn.jsdelivr.net/npm/@tiptap/pm@2/dropcursor/+esm"
pin "@tiptap/pm/gapcursor", to: "https://cdn.jsdelivr.net/npm/@tiptap/pm@2/gapcursor/+esm"
pin "@tiptap/pm/history", to: "https://cdn.jsdelivr.net/npm/@tiptap/pm@2/history/+esm"
pin "@tiptap/pm/inputrules", to: "https://cdn.jsdelivr.net/npm/@tiptap/pm@2/inputrules/+esm"
