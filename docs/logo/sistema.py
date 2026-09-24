from PIL import Image, ImageFilter, ImageEnhance, ImageOps, ImageDraw
import numpy as np
im=Image.open('originale.jpg').convert('RGB')
w,h=im.size
# quadrato: si aggiunge nero sopra e sotto (non si taglia la cornice)
lato=max(w,h)
q=Image.new('RGB',(lato,lato),(4,6,14)); q.paste(im,((lato-w)//2,(lato-h)//2))
# via la trama dello schermo: un velo di sfocatura, poi si rimpicciolisce
q=q.filter(ImageFilter.GaussianBlur(1.6)).resize((1024,1024),Image.LANCZOS)
a=np.asarray(q).astype(float)/255
# livelli: il nero vero al nero, il bianco al bianco
basso=np.percentile(a,1.5,axis=(0,1)); alto=np.percentile(a,99.7,axis=(0,1))
a=np.clip((a-basso)/(alto-basso),0,1)
# le ombre più profonde (lo sfondo era grigiastro dalla foto), le luci intatte
a=a**1.25
# meno dominante ciano nei grigi scuri: si abbassa un po' il verde/blu solo nelle ombre
l=a.mean(axis=2,keepdims=True)
ombre=np.clip(1-l*2.2,0,1)
a[...,1:2]-=0.035*ombre; a[...,2:3]-=0.02*ombre
a=np.clip(a,0,1)
out=Image.fromarray((a*255).astype('uint8'))
out=ImageEnhance.Color(out).enhance(1.22)
out=ImageEnhance.Contrast(out).enhance(1.08)
out=out.filter(ImageFilter.UnsharpMask(radius=2.2,percent=90,threshold=2))
out.save('logo_sistemato.png')
# confronto: prima e dopo, fianco a fianco
prima=Image.open('originale.jpg').convert('RGB').resize((512,500))
c=Image.new('RGB',(1044,512),(255,255,255)); c.paste(prima,(0,6)); c.paste(out.resize((512,512)),(532,0)); c.save('confronto.png')
