hl.config({ animations = { enabled = true } })

hl.curve("linear", { type = "bezier", points = { {0.0, 0.0}, {1.0, 1.0} } })
hl.curve("snappy", { type = "bezier", points = { {0.2, 0.9}, {0.3, 1.0} } })
hl.curve("quick_out", { type = "bezier", points = { {0.0, 0.0}, {0.2, 1.0} } })

hl.animation({ leaf = "windowsIn", enabled = true, speed = 2.5, bezier = "snappy", style = "popin 90%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2, bezier = "quick_out", style = "popin 90%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3, bezier = "snappy", style = "slide" })
hl.animation({ leaf = "border", enabled = true, speed = 1, bezier = "linear" })
hl.animation({ leaf = "fade", enabled = true, speed = 2, bezier = "snappy" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "snappy", style = "slide" })
hl.animation({ leaf = "windows", enabled = true, speed = 2.5, bezier = "snappy" })
