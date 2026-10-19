#!/usr/bin/env python3
"""Extract the supplied die-cut sticker without regenerating its pixels."""
from pathlib import Path
import shutil

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'apps/macos/Assets'
SOURCE = ROOT / 'media/icon-sources'
PREVIEW = ROOT / 'exports/icon-preview'

# Traced just inside the sticker's paper edge, excluding its cast shadow.
# Keep the white die-cut border and the individual whisker extensions.
OUTLINE = [
    (995,73),(1007,74),(1016,86),(1015,101),(1022,105),(1050,93),
    (1072,94),(1105,114),(1132,157),(1153,213),(1174,292),(1184,365),
    (1190,413),(1189,435),(1197,459),(1192,486),(1196,525),
    (1222,571),(1250,614),(1256,654),(1259,687),(1265,694),
    (1300,686),(1359,672),(1386,671),(1402,677),(1415,687),(1414,696),
    (1405,703),(1339,723),(1290,741),(1281,750),(1292,759),
    (1340,771),(1405,787),(1457,800),(1477,810),(1487,829),
    (1483,841),(1475,846),(1453,845),(1389,833),(1310,830),(1289,831),
    (1284,836),(1321,853),(1390,885),(1466,925),(1514,961),
    (1525,975),(1520,988),(1510,993),(1498,990),(1441,967),
    (1351,924),(1337,928),(1354,947),(1390,981),(1434,1032),
    (1455,1072),(1456,1084),(1444,1094),(1429,1091),(1394,1060),
    (1352,1023),(1312,994),(1296,990),(1321,1031),(1357,1091),
    (1388,1153),(1391,1172),(1379,1186),(1367,1188),(1355,1177),
    (1307,1115),(1263,1053),(1230,1009),(1217,1004),(1205,1021),
    (1168,1074),(1130,1136),(1080,1201),(1038,1238),(991,1260),
    (945,1271),(885,1268),(812,1252),(739,1239),(669,1229),
    (626,1224),(617,1231),(602,1276),(590,1287),(579,1288),
    (569,1280),(561,1267),(562,1255),(572,1220),(569,1210),
    (535,1199),(507,1188),(488,1172),(480,1171),(463,1196),
    (424,1260),(386,1323),(373,1356),(360,1371),(350,1374),
    (339,1369),(334,1357),(336,1343),(344,1315),(343,1307),
    (338,1303),(330,1305),(321,1315),(288,1360),(270,1367),
    (258,1375),(246,1376),(235,1367),(230,1357),(240,1337),
    (276,1272),(318,1213),(362,1160),(400,1116),(403,1106),
    (393,1085),(382,1079),(366,1084),(301,1126),(236,1180),
    (154,1254),(138,1263),(126,1259),(119,1250),(120,1236),
    (132,1220),(194,1151),(260,1094),(270,1082),(267,1075),
    (258,1074),(241,1081),
    (190,1106),(100,1141),
    (85,1144),(76,1138),(75,1125),(89,1112),(155,1071),
    (237,1019),(290,981),(316,963),(317,956),(307,951),
    (269,958),(198,979),(119,999),(108,999),(100,989),
    (99,975),(112,962),(183,934),(248,911),(288,892),
    (287,882),(264,854),(249,814),(217,737),(187,662),
    (156,575),(134,498),(122,441),(122,396),(133,355),
    (159,322),(193,302),(238,293),(281,292),(328,299),
    (375,316),(421,343),(460,372),(505,410),(514,412),
    (513,401),(494,359),(469,305),(466,287),(475,279),
    (490,282),(521,314),(529,322),(536,308),(548,304),
    (560,317),(578,356),(595,404),(603,417),(615,416),
    (689,397),(756,383),(811,371),(833,371),(837,366),
    (833,344),(817,296),(803,262),(804,245),(813,243),
    (826,253),(845,290),(858,311),(868,315),(880,295),
    (909,223),(938,157),(968,101),(987,78),
]


def smooth_outline(points):
    """Short cubic segments keep the paper edge smooth at original resolution."""
    p = np.asarray(points, dtype=float)
    result = []
    for i in range(len(p)):
        a, b, c, d = p[(i-1) % len(p)], p[i], p[(i+1) % len(p)], p[(i+2) % len(p)]
        for t in np.linspace(0, 1, 12, endpoint=False):
            q = .5 * ((2*b) + (-a+c)*t + (2*a-5*b+4*c-d)*t*t + (-a+3*b-3*c+d)*t*t*t)
            result.append(tuple(q))
    return result


def main():
    ASSETS.mkdir(parents=True, exist_ok=True)
    PREVIEW.mkdir(parents=True, exist_ok=True)
    source = Image.open(SOURCE / 'cat-sticker.png').convert('RGBA')
    factor = 3
    mask = Image.new('L', (source.width*factor, source.height*factor))
    ImageDraw.Draw(mask).polygon([(round(x*factor), round(y*factor)) for x,y in smooth_outline(OUTLINE)], fill=255)
    mask = mask.resize(source.size, Image.Resampling.LANCZOS)
    source.putalpha(mask)
    crop = source.crop(mask.getbbox())
    crop.save(ASSETS / 'CatSticker.png')
    # Square source with a small transparent margin for AppKit's aspect fit.
    side = max(crop.size) + 32
    icon = Image.new('RGBA', (side, side))
    icon.alpha_composite(crop, ((side-crop.width)//2, (side-crop.height)//2))
    icon.resize((512,512), Image.Resampling.LANCZOS).save(ASSETS / 'StatusIcon.png')
    # Keep the supplied photo itself, including the dark fisheye surround.
    shutil.copy2(SOURCE / 'prison-fisheye.jpg', ASSETS / 'CleanupPhoto.jpg')
    preview = Image.new('RGB', (1080,620), '#ececef')
    for n,color in enumerate(('#f5f5f7','#28282b')):
        tile = Image.new('RGBA',(500,500),color)
        small = icon.copy();small.thumbnail((480,480),Image.Resampling.LANCZOS)
        tile.alpha_composite(small,((500-small.width)//2,(500-small.height)//2))
        preview.paste(tile.convert('RGB'),(20+n*540,20))
        for i,size in enumerate((18,22,36,44,72)):
            thumb=icon.resize((size,size),Image.Resampling.LANCZOS)
            preview.paste(thumb,(35+n*540+i*92,540),thumb)
    preview.save(PREVIEW / 'sticker-light-dark.png')
    print('Saved CatSticker.png, StatusIcon.png, CleanupPhoto.jpg and light/dark preview')


if __name__ == '__main__':
    main()
