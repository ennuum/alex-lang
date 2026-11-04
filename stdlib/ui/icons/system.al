# System icon helpers.
# The backend decides how a named system icon is resolved.

use ui.icon as icon

func load(name, size=20):
    return icon.from_builtin(name, size)
