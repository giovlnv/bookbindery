# static Fraunces instances from the google/fonts variable file (see fonts/README.md)
import sys
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
src = sys.argv[1]
for wght, style in [(400, "Regular"), (500, "Medium"), (600, "SemiBold")]:
    f = instantiateVariableFont(TTFont(src), {"wght": wght, "opsz": 28, "SOFT": 0, "WONK": 0})
    n = f["name"]
    fam = "Fraunces" if style == "Regular" else "Fraunces " + style
    for rec in list(n.names):
        if rec.nameID in (1, 2, 3, 4, 6, 16, 17) or rec.nameID >= 256:
            n.removeNames(nameID=rec.nameID)
    n.setName(fam, 1, 3, 1, 0x409)
    n.setName("Regular", 2, 3, 1, 0x409)
    n.setName("Fraunces-" + style + ";bookbindery", 3, 3, 1, 0x409)
    n.setName("Fraunces " + style, 4, 3, 1, 0x409)
    n.setName("Fraunces-" + style, 6, 3, 1, 0x409)
    if style != "Regular":
        n.setName("Fraunces", 16, 3, 1, 0x409)
        n.setName(style, 17, 3, 1, 0x409)
    f["OS/2"].usWeightClass = wght
    f.save("out/Fraunces-" + style + ".ttf")
