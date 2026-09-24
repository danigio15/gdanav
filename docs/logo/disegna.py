import math, sys
cx,cy,r=512,512,285
def pt(a):
    a=math.radians(a); return (cx+r*math.cos(a), cy+r*math.sin(a))
s=pt(-40); e=pt(0)
arco=f"M {s[0]:.1f} {s[1]:.1f} A {r} {r} 0 1 0 {e[0]:.1f} {e[1]:.1f}"
g=arco+" L 690 512"
def ruota(punti,cx0,cy0,size,ang):
    a=math.radians(ang); c,s_=math.cos(a),math.sin(a)
    return [(cx0+(x*size)*c-(y*size)*s_, cy0+(x*size)*s_+(y*size)*c) for x,y in punti]
def percorso(pts): return "M "+" L ".join(f"{x:.1f} {y:.1f}" for x,y in pts)+" Z"
A=[(0,-1),(0.64,0.74),(0,0.4),(-0.64,0.74)]
ax,ay,size=505,515,150
freccia=percorso(ruota(A,ax,ay,size,45))
# il fulmine, dritto, al centro del corpo della freccia
bx,by=ruota([(0,0.12)],ax,ay,size,45)[0]
F=[(0.18,-1),(-0.38,0.12),(-0.02,0.12),(-0.2,1),(0.4,-0.18),(0.04,-0.18)]
fulmine=percorso([(bx+x*62,by+y*62) for x,y in F])
fondo = sys.argv[1] if len(sys.argv)>1 else 'pieno'
rett = '<rect width="1024" height="1024" fill="url(#sfondo)"/>' if fondo=='pieno' else ''
svg=f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
  <radialGradient id="sfondo" cx="35%" cy="25%" r="90%">
    <stop offset="0" stop-color="#1D3163"/><stop offset="0.55" stop-color="#0F1B3D"/><stop offset="1" stop-color="#070D22"/>
  </radialGradient>
  <linearGradient id="strada" x1="200" y1="760" x2="800" y2="280" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#1E8BFF"/><stop offset="0.48" stop-color="#43B0FF"/><stop offset="0.8" stop-color="#FFA24A"/><stop offset="1" stop-color="#FF7A1A"/>
  </linearGradient>
  <linearGradient id="punta" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#FFB45E"/><stop offset="1" stop-color="#FF6A00"/>
  </linearGradient>
  <filter id="alone" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="24"/></filter>
</defs>
{rett}
<path d="{g}" fill="none" stroke="url(#strada)" stroke-width="150" stroke-linecap="round" stroke-linejoin="round" opacity="0.5" filter="url(#alone)"/>
<path d="{g}" fill="none" stroke="url(#strada)" stroke-width="128" stroke-linecap="round" stroke-linejoin="round"/>
<path d="{arco}" fill="none" stroke="#FFFFFF" stroke-opacity="0.9" stroke-width="12" stroke-linecap="round" stroke-dasharray="44 48"/>
<path d="{freccia}" fill="url(#punta)" stroke="#FFFFFF" stroke-width="20" stroke-linejoin="round" filter="url(#alone)" opacity="0.6"/>
<path d="{freccia}" fill="url(#punta)" stroke="#FFFFFF" stroke-width="20" stroke-linejoin="round"/>
<path d="{fulmine}" fill="#0F1B3D"/>
</svg>'''
print(svg)
