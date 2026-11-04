# Custom file icons.

use ui.icon as icon

func load(path, size=20):
    return icon.from_file(path, size)

func png(path, size=20):
    return icon.from_file(path, size)

func jpeg(path, size=20):
    return icon.from_file(path, size)

func bmp(path, size=20):
    return icon.from_file(path, size)

func ico(path, size=20):
    return icon.from_file(path, size)
