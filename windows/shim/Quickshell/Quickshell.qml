pragma Singleton
import QtQml
import LonghandHost

// The `Quickshell` singleton, as far as the page calls it.
QtObject {
  function env(name) { return Host.env(name) }
  function execDetached(command) { Host.execDetached(command) }
}
