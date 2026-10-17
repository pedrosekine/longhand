"""Historical studies only. Current logo: launcher/longhand-mark.svg."""
from pathlib import Path
import math
import subprocess
import html

OUT = Path(__file__).resolve().parent
INK, PAPER, QUIET, LINE = '#222320', '#f5f2ea', '#696960', '#d8d6cd'


def smooth(points):
    """Closed Catmull-Rom contour expressed as cubic Bezier segments."""
    result = [f'M {points[0][0]:.3f},{points[0][1]:.3f}']
    for i, p in enumerate(points):
        before, after, following = points[i-1], points[(i+1)%len(points)], points[(i+2)%len(points)]
        a = (p[0]+(after[0]-before[0])/6, p[1]+(after[1]-before[1])/6)
        b = (after[0]-(following[0]-p[0])/6, after[1]-(following[1]-p[1])/6)
        result.append(f'C {a[0]:.3f},{a[1]:.3f} {b[0]:.3f},{b[1]:.3f} {after[0]:.3f},{after[1]:.3f}')
    return ' '.join(result) + ' Z'


def seal(depth=8.6, organic=False):
    points = []
    for i in range(100):
        t = 2*math.pi*i/100 - math.pi/2
        r = 35 + depth*math.cos(5*(t+math.pi/2))
        if organic:
            r += 3.8*math.cos(t-.3) + 2.8*math.sin(2*t+.5) + 1.6*math.cos(3*t-.4)
        x, y = r*math.cos(t), r*math.sin(t)
        if organic:
            x, y = 1.015*x + .19*y, .96*y
        points.append((50+x, 50+y))
    return smooth(points)


def shoulder(rounding=.28):
    vertices = [(50+47*math.cos(t), 52+47*math.sin(t)) for t in [2*math.pi*i/5-math.pi/2 for i in range(5)]]
    parts=[]
    for i,v in enumerate(vertices):
        previous, following = vertices[i-1], vertices[(i+1)%5]
        entry = tuple(v[j]*(1-rounding)+previous[j]*rounding for j in (0,1))
        leave = tuple(v[j]*(1-rounding)+following[j]*rounding for j in (0,1))
        parts.append(f'{"M" if i==0 else "L"} {entry[0]:.3f},{entry[1]:.3f} Q {v[0]:.3f},{v[1]:.3f} {leave[0]:.3f},{leave[1]:.3f}')
    return ' '.join(parts)+' Z'


studies = [
    ('seal', 'A', 'The seal', 'Open, balanced, softly scalloped.', seal(6.8), seal(4.6), 'Shallower lobes'),
    ('shoulder', 'B', 'The shoulder', 'Compact, weighty, deliberately simple.', shoulder(), shoulder(.40), 'Softer corners'),
    ('impression', 'C', 'The impression', 'Uneven pressure, a slight forward lean.', seal(4.8, True), seal(3.4, True), 'Quieter contour'),
]


def mark(path,x,y,size,fill=INK):
    return f'<path d="{path}" transform="translate({x},{y}) scale({size/100})" fill="{fill}"/>'


def text(x,y,value,size=18,fill=INK,family='sans-serif',weight=400):
    return f'<text x="{x}" y="{y}" fill="{fill}" font-family="{family}" font-size="{size}" font-weight="{weight}">{html.escape(value)}</text>'


def svg(content,w,h):
    return f'<svg xmlns="http://www.w3.org/2000/svg" data-longhand-status="historical-reference" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{content}</svg>'


board = [f'<rect width="1440" height="1320" fill="{PAPER}"/>']
board += [text(64,64,'LONGHAND  /  IDENTITY STUDIES',17,QUIET), text(64,130,'A signature for a writing tool.',40,family='serif'), text(64,172,'Round one · five-sided forms · one colour · October 2026',18,QUIET)]
for i,(key,letter,name,description,path,alt,alt_name) in enumerate(studies):
    left = 64+i*448
    board += [f'<line x1="{left}" y1="218" x2="{left+416}" y2="218" stroke="{LINE}"/>',text(left,255,f'{letter}  /  {name}',23),text(left,288,description,16,QUIET)]
    board += [mark(path,left+98,328,220)]
    board += [mark(alt,left+8,586,64),text(left+90,616,alt_name,17,QUIET)]
    board += [text(left,702,'SMALL-SIZE STUDIES · PIXELS AT FULL RESOLUTION',12,QUIET)]
    for offset,size in [(0,16),(64,24),(136,32)]:
        board += [mark(path,left+offset,730+(32-size)/2,size),text(left+offset,794,str(size)+' px',13,QUIET)]
    board += [f'<rect x="{left+235}" y="717" width="64" height="64" rx="14" fill="{INK}"/>',mark(path,left+247,729,40,PAPER),text(left+235,805,'Reversed',13,QUIET)]
    board += [f'<line x1="{left}" y1="845" x2="{left+416}" y2="845" stroke="{LINE}"/>',text(left,880,'REPEATED THROUGH THE PRODUCT',13,QUIET)]
    # A compact launcher row and a page header are context studies, not UI changes.
    board += [f'<rect x="{left}" y="908" width="416" height="77" rx="12" fill="{INK}"/>',mark(path,left+19,930,32,PAPER),text(left+69,950,'Longhand',21,PAPER),text(left+326,950,'Open',15,'#bdbfb5')]
    board += [f'<rect x="{left}" y="1008" width="416" height="220" fill="#fffdf7" stroke="{LINE}"/>',mark(path,left+18,1026,22),text(left+53,1043,'Longhand',16),text(left+323,1043,'Today',14,QUIET),f'<line x1="{left+18}" y1="1061" x2="{left+398}" y2="1061" stroke="{LINE}"/>',text(left+25,1116,'Saturday, 17 October',24,family='serif'),text(left+25,1162,'A little space to think.',20,QUIET,family='serif'),mark(path,left+365,1190,19)]
    (OUT/f'{key}.svg').write_text(svg(f'<title>Longhand study {letter}: {name}</title>'+mark(path,0,0,100,'currentColor'),100,100))
    (OUT/f'{key}-alternate.svg').write_text(svg(f'<title>Longhand study {letter}: {alt_name}</title>'+mark(alt,0,0,100,'currentColor'),100,100))
board += [text(64,1282,'Explorations only. The recurring emblem stays the same; scale and surrounding surface change.',16,QUIET)]
(OUT/'comparison.svg').write_text(svg(''.join(board),1440,1320))
subprocess.run(['rsvg-convert',str(OUT/'comparison.svg'),'-o',str(OUT/'comparison.png')],check=True)
print(OUT/'comparison.png')
