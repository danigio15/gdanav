"""La freccia di navigazione, come quella di Waze.

«Mi cambi lo stile della freccia, la voglio come Waze.» Due toni di celeste —
la meta' sinistra piu' chiara, la destra piu' scura, come una freccia piegata
sul dorso — un bordo bianco spesso e un'ombra morbida; niente tondo dietro.

    python3 tools/disegna_freccia.py packages/gdanav_app/assets/segnaposto/freccia.png
"""
import sys
from PIL import Image, ImageDraw, ImageFilter
S=4; N=192; W=N*S
def pt(x,y): return (x*W, y*W)
# La freccia, in su: punta, ala destra, incavo, ala sinistra.
punta=(0.5,0.13); destra=(0.80,0.83); incavo=(0.5,0.67); sinistra=(0.20,0.83)
forma=[punta,destra,incavo,sinistra]
def gonfia(poly, r, img, colore):
    d=ImageDraw.Draw(img)
    pts=[pt(*p) for p in poly]
    d.polygon(pts, fill=colore)
    for i in range(len(pts)):
        a=pts[i]; b=pts[(i+1)%len(pts)]
        d.line([a,b], fill=colore, width=int(2*r))
        d.ellipse([a[0]-r,a[1]-r,a[0]+r,a[1]+r], fill=colore)
img=Image.new("RGBA",(W,W),(0,0,0,0))
# Ombra
ombra=Image.new("RGBA",(W,W),(0,0,0,0))
gonfia([(x,y+0.025) for x,y in forma], 0.06*W, ombra, (0,0,0,120))
ombra=ombra.filter(ImageFilter.GaussianBlur(0.035*W))
img=Image.alpha_composite(img,ombra)
# Bordo bianco
bordo=Image.new("RGBA",(W,W),(0,0,0,0))
gonfia(forma, 0.055*W, bordo, (255,255,255,255))
img=Image.alpha_composite(img,bordo)
# Due toni, come Waze: la meta' sinistra piu' chiara, la destra piu' scura.
chiaro=Image.new("RGBA",(W,W),(0,0,0,0))
gonfia([punta,incavo,sinistra], 0.012*W, chiaro, (92,205,255,255))
scuro=Image.new("RGBA",(W,W),(0,0,0,0))
gonfia([punta,destra,incavo], 0.012*W, scuro, (24,146,232,255))
img=Image.alpha_composite(img,scuro)
img=Image.alpha_composite(img,chiaro)
img.resize((N,N),Image.LANCZOS).save(sys.argv[1])
