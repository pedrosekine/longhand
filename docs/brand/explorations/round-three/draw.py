"""Historical studies only. Current logo: launcher/longhand-mark.svg."""
from pathlib import Path
import ast
import html
import math
import subprocess

OUT = Path(__file__).resolve().parent
REPO = OUT.parents[3]
INK, PAPER, QUIET, LINE = '#222320', '#f5f2ea', '#696960', '#d8d6cd'

# Reuse the exact round-two contour without rerunning that round's exports.
tree = ast.parse((OUT.parent/'round-two/draw.py').read_text())
namespace = {'math': math}
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='contour'],type_ignores=[]),'<round-two-contour>','exec'), namespace)
contour = namespace['contour']


def mark(path,x,y,size,fill=INK):
    return f'<path d="{path}" transform="translate({x},{y}) scale({size/100})" fill="{fill}"/>'


def text(x,y,value,size=18,fill=INK,family='sans-serif'):
    return f'<text x="{x}" y="{y}" fill="{fill}" font-family="{family}" font-size="{size}">{html.escape(value)}</text>'


def svg(content,w,h):
    return f'<svg xmlns="http://www.w3.org/2000/svg" data-longhand-status="historical-reference" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{content}</svg>'


studies = [
    ('original','Original A2','The reference you chose.',8.8,5.0),
    ('soft-cut','Softer cuts','Slightly shallower, more rounded recesses.',8.4,4.3),
    ('open-cut','Open cuts','Slightly deeper, wider recesses.',9.4,4.4),
]
board=[f'<rect width="1200" height="1050" fill="{PAPER}"/>',text(48,52,'LONGHAND / A2 / OPTICAL REFINEMENTS',15,QUIET),text(48,110,'Three close relatives.',38,family='serif'),text(48,150,'The silhouette stays. Only the five recesses change.',18,QUIET)]
for i,(key,name,description,depth,breadth) in enumerate(studies):
    x=48+i*384
    path=contour(depth,breadth)
    board += [f'<line x1="{x}" y1="195" x2="{x+336}" y2="195" stroke="{LINE}"/>',text(x,232,name,24),text(x,263,description,15,QUIET),mark(path,x+62,298,200)]
    board += [text(x,540,'DARK MARK',12,QUIET)]
    for offset,size in [(0,16),(65,24),(138,32),(222,48)]:
        board += [mark(path,x+offset,566+(48-size)/2,size),text(x+offset,640,str(size),13,QUIET)]
    board += [f'<rect x="{x}" y="669" width="336" height="110" rx="12" fill="{INK}"/>',text(x+17,696,'LIGHT MARK',12,'#bdbfb5')]
    for offset,size in [(17,16),(82,24),(155,32),(239,48)]:
        board += [mark(path,x+offset,711+(48-size)/2,size,PAPER)]
    # Same contrast and padding as the eventual launcher asset.
    board += [f'<rect x="{x}" y="816" width="80" height="80" rx="17" fill="{INK}"/>',mark(path,x+7,823,66,PAPER),text(x+103,863,'Longhand',24,family='serif')]
    (OUT/f'{key}.svg').write_text(svg(f'<title>Longhand A2: {name}</title>'+mark(path,0,0,100,'currentColor'),100,100))
board += [text(48,976,'16 / 24 / 32 / 48 px at full image resolution. Same geometry in both polarities.',16,QUIET),text(48,1007,'Launcher trial: Open cuts. The original A2 remains preserved alongside both refinements.',16,QUIET)]
(OUT/'comparison.svg').write_text(svg(''.join(board),1200,1050))
subprocess.run(['rsvg-convert',str(OUT/'comparison.svg'),'-o',str(OUT/'comparison.png')],check=True)

selected=contour(9.4,4.4)
# The mark is separate from its dark launcher tile so future product surfaces can
# use their own colour and surrounding surface without redrawing the identity.
master=svg('<title>Longhand</title><desc>A five-lobed seal with broad crowns and five rounded recesses.</desc>'+mark(selected,0,0,100,'currentColor'),100,100)
(OUT/'longhand-mark.svg').write_text(master)
tile=svg('<title>Longhand</title><rect x="6.25" y="6.25" width="87.5" height="87.5" rx="18.75" fill="#26262b"/>'+mark(selected,13,13,74,'#f2efe8'),100,100)
(OUT/'longhand.svg').write_text(tile)
subprocess.run(['rsvg-convert',str(OUT/'longhand.svg'),'-w','256','-h','256','-o',str(OUT/'launcher-preview.png')],check=True)
print(OUT/'comparison.png')
