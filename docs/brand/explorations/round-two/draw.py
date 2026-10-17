"""Historical studies only. Current logo: launcher/longhand-mark.svg."""
from pathlib import Path
import math
import html
import subprocess

OUT = Path(__file__).resolve().parent
INK, PAPER, QUIET, LINE = '#222320', '#f5f2ea', '#696960', '#d8d6cd'


def contour(depth, breadth, pressure=0, rotation=0, flatten=0):
    points = []
    for i in range(240):
        t = 2*math.pi*i/240-math.pi/2
        # High-order valleys retain broad circular crowns between indentations.
        phase = t+math.pi/2 + pressure*.018*math.sin(t+.6)
        indent = ((1-math.cos(5*phase))/2)**breadth
        r = 42-depth*indent
        # Small, deliberately bounded adjustments; no free-form blob warping.
        r += pressure*(.7*math.cos(t-.3)+.45*math.sin(2*t+.4))
        x,y = r*math.cos(t),r*math.sin(t)
        if flatten:
            # Squared-off crowns, smoothly blended with the circular contour.
            exponent = 2.7
            sx = math.copysign(abs(math.cos(t))**(2/exponent), math.cos(t))*42
            sy = math.copysign(abs(math.sin(t))**(2/exponent), math.sin(t))*42
            x = x*(1-flatten)+sx*(r/42)*flatten
            y = y*(1-flatten)+sy*(r/42)*flatten
        x,y = x*math.cos(rotation)-y*math.sin(rotation),x*math.sin(rotation)+y*math.cos(rotation)
        points.append((50+x,50+y))
    result = [f'M {points[0][0]:.3f},{points[0][1]:.3f}']
    for i,p in enumerate(points):
        previous,nxt,following=points[i-1],points[(i+1)%len(points)],points[(i+2)%len(points)]
        a=(p[0]+(nxt[0]-previous[0])/6,p[1]+(nxt[1]-previous[1])/6)
        b=(nxt[0]-(following[0]-p[0])/6,nxt[1]-(following[1]-p[1])/6)
        result.append(f'C {a[0]:.3f},{a[1]:.3f} {b[0]:.3f},{b[1]:.3f} {nxt[0]:.3f},{nxt[1]:.3f}')
    return ' '.join(result)+' Z'


def mark(path,x,y,size,fill=INK):
    return f'<path d="{path}" transform="translate({x},{y}) scale({size/100})" fill="{fill}"/>'


def text(x,y,value,size=18,fill=INK,family='sans-serif'):
    return f'<text x="{x}" y="{y}" fill="{fill}" font-family="{family}" font-size="{size}">{html.escape(value)}</text>'


def svg(content,w,h):
    return f'<svg xmlns="http://www.w3.org/2000/svg" data-longhand-status="historical-reference" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{content}</svg>'


studies = [
    ('a1-scalloped', 'A1', 'Broad scallops', 'Wider crowns; five rounded recesses.', contour(8,2.8)),
    ('a2-cut-seal', 'A2', 'Cut seal', 'A fuller disc; five short, deeper cuts.', contour(8.8,5.0)),
    ('c1-pressed', 'C1', 'Measured pressure', 'The same rhythm, with restrained inequality.', contour(7.4,2.8,1.0,.10)),
    ('c2-oblique', 'C2', 'Oblique impression', 'A broader body, firmer shoulders, a small turn.', contour(7.8,3.3,.8,.23,.38)),
]

board = [f'<rect width="1200" height="1190" fill="{PAPER}"/>',text(52,53,'LONGHAND / IDENTITY STUDIES / ROUND TWO',15,QUIET),text(52,108,'Broader lobes. More deliberate contours.',35,family='serif'),text(52,145,'A develops the seal. C develops the impression. Five parts throughout.',17,QUIET)]
for i,(key,code,name,description,path) in enumerate(studies):
    left,top = 52+(i%2)*572, 185+(i//2)*475
    board += [f'<line x1="{left}" y1="{top}" x2="{left+520}" y2="{top}" stroke="{LINE}"/>',text(left,top+38,f'{code} / {name}',23),text(left,top+70,description,16,QUIET)]
    board += [mark(path,left+13,top+101,210),f'<rect x="{left+305}" y="{top+129}" width="126" height="126" rx="27" fill="{INK}"/>',mark(path,left+316,top+140,104,PAPER)]
    board += [text(left+18,top+347,'16',13,QUIET),text(left+70,top+347,'24',13,QUIET),text(left+132,top+347,'32 px',13,QUIET)]
    for offset,size in [(16,16),(66,24),(126,32)]:
        board += [mark(path,left+offset,top+295+(32-size)/2,size)]
    board += [mark(path,left+291,top+303,22),text(left+324,top+321,'Longhand',23,family='serif')]
    board += [f'<rect x="{left}" y="{top+379}" width="520" height="61" rx="10" fill="{INK}"/>',mark(path,left+17,top+395,29,PAPER),text(left+65,top+418,'Longhand',19,PAPER),text(left+427,top+417,'Open',14,'#bdbfb5')]
    (OUT/f'{key}.svg').write_text(svg(f'<title>Longhand {code}: {name}</title>'+mark(path,0,0,100,'currentColor'),100,100))
board += [text(52,1160,'Explorations · small sizes labelled at full image resolution · launcher and wordmark context',15,QUIET)]
(OUT/'comparison.svg').write_text(svg(''.join(board),1200,1190))
subprocess.run(['rsvg-convert',str(OUT/'comparison.svg'),'-o',str(OUT/'comparison.png')],check=True)
print(OUT/'comparison.png')
