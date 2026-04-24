// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/app"
import {Hooks as PUIHooks} from "pui"

const TaskScheduleForm = {
  mounted() {
    this.localInput = this.el.querySelector("#task-next-run-local")
    this.utcInput = this.el.querySelector("#task-next-run-input")
    this.timezoneInput = this.el.querySelector("#task-browser-timezone")

    this.syncUtcValue = () => {
      if (!this.localInput || !this.utcInput) return

      if (this.timezoneInput) {
        this.timezoneInput.value = Intl.DateTimeFormat().resolvedOptions().timeZone || "Etc/UTC"
      }

      if (this.localInput.value === "") {
        this.utcInput.value = ""
        return
      }

      const localDate = new Date(this.localInput.value)
      if (Number.isNaN(localDate.getTime())) {
        return
      }

      this.utcInput.value = this.toUtcLocalInput(localDate)
    }

    this.inputHandler = () => this.syncUtcValue()

    if (this.localInput && this.utcInput) {
      const utcValue = this.localInput.dataset.utcValue || this.utcInput.value

      if (utcValue) {
        const utcDate = this.parseUtcInput(utcValue)
        if (utcDate) {
          this.localInput.value = this.toLocalInputValue(utcDate)
        }
      }

      this.localInput.addEventListener("input", this.inputHandler)
      this.localInput.addEventListener("change", this.inputHandler)
      this.syncUtcValue()
    } else if (this.timezoneInput) {
      this.timezoneInput.value = Intl.DateTimeFormat().resolvedOptions().timeZone || "Etc/UTC"
    }
  },

  destroyed() {
    if (this.localInput && this.inputHandler) {
      this.localInput.removeEventListener("input", this.inputHandler)
      this.localInput.removeEventListener("change", this.inputHandler)
    }
  },

  parseUtcInput(value) {
    const hasSeconds = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/.test(value)
    const hasMinutes = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value)
    const normalized = hasMinutes ? `${value}:00` : value
    const utc = normalized.endsWith("Z") ? normalized : `${normalized}Z`
    const date = new Date(utc)

    if (Number.isNaN(date.getTime())) return null
    if (!hasMinutes && !hasSeconds && !value.endsWith("Z")) return null
    return date
  },

  toLocalInputValue(date) {
    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, "0")
    const day = String(date.getDate()).padStart(2, "0")
    const hours = String(date.getHours()).padStart(2, "0")
    const minutes = String(date.getMinutes()).padStart(2, "0")
    return `${year}-${month}-${day}T${hours}:${minutes}`
  },

  toUtcLocalInput(date) {
    const year = date.getUTCFullYear()
    const month = String(date.getUTCMonth() + 1).padStart(2, "0")
    const day = String(date.getUTCDate()).padStart(2, "0")
    const hours = String(date.getUTCHours()).padStart(2, "0")
    const minutes = String(date.getUTCMinutes()).padStart(2, "0")
    return `${year}-${month}-${day}T${hours}:${minutes}`
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...PUIHooks, TaskScheduleForm},
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
