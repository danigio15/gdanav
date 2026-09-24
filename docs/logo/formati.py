from PIL import Image, ImageDraw
import sys, os
R=sys.argv[1]
logo=Image.open('logo_sistemato.png').convert('RGBA')
N=logo.size[0]
def arrotonda(img, raggio=0.2, margine=0.004):
    n=img.size[0]
    m=Image.new('L',(n*4,n*4),0)
    d=ImageDraw.Draw(m); k=int(n*4*margine)
    d.rounded_rectangle([k,k,n*4-k-1,n*4-k-1],radius=int(n*4*raggio),fill=255)
    m=m.resize((n,n),Image.LANCZOS)
    out=img.copy(); out.putalpha(m); return out
tondo=arrotonda(logo)
os.makedirs('out',exist_ok=True)
logo.convert('RGB').resize((512,512),Image.LANCZOS).save('out/play_icona_512.png')
tondo.save('out/logo_1024.png')
FONDO=(5,8,16,255)
for nome,leg,ad in [('mdpi',48,108),('hdpi',72,162),('xhdpi',96,216),('xxhdpi',144,324),('xxxhdpi',192,432)]:
    tondo.resize((leg,leg),Image.LANCZOS).save(f'{R}/mipmap-{nome}/ic_launcher.png')
    Image.new('RGBA',(ad,ad),FONDO).save(f'{R}/mipmap-{nome}/ic_launcher_background.png')
    # il logo intero dentro la parte che il launcher mostra (i due terzi centrali)
    lato=int(ad*0.70); pp=Image.new('RGBA',(ad,ad),(0,0,0,0))
    pp.paste(tondo.resize((lato,lato),Image.LANCZOS),((ad-lato)//2,(ad-lato)//2))
    pp.save(f'{R}/mipmap-{nome}/ic_launcher_foreground.png')
print('ok')
