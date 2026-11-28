"""
Welcome-screen animation: removes the scenery from the original GIF (welcome_source.gif).

Only the alpha channel is generated; the car and the two characters keep their original
pixels (fully transparent pixels are zeroed). Frames cut off by the GIF canvas are faded
at the edges so no rectangle shows. Run: python3 cut_welcome_frames.py
"""
import json, os
import numpy as np, cv2
from PIL import Image, ImageSequence

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ANDROID = os.path.join(ROOT, "android-kherja/app/src/main/res/drawable-nodpi")
IOS = os.path.join(ROOT, "ios-kherja/KHERJA/Assets.xcassets")
P={
0:"196,202 200,198 212,197 225,197 231,199 235,204 238,210 239,208 243,208 244,212 240,213 242,218 243,224 243,238 241,239 233,239 232,237 198,237 195,240 186,239 185,230 185,222 187,217 189,213 185,212 185,209 189,208 191,210 193,205",
1:"180,165 186,156 200,154 225,153 250,154 270,156 278,163 284,175 291,188 294,181 300,180 305,181 306,186 303,190 296,192 297,196 303,202 307,208 308,215 307,235 305,248 304,258 301,263 285,263 282,255 268,252 180,252 170,254 168,262 163,263 150,262 147,250 145,240 145,222 147,208 152,200 160,196 163,191 157,189 153,185 153,181 157,180 164,181 167,186 168,190 173,179",
2:"0,290 20,268 32,250 45,236 42,232 14,230 11,215 16,205 33,203 41,207 44,220 50,226 66,205 85,175 100,148 112,130 125,119 150,110 185,104 220,99 260,97 300,99 320,103 335,112 345,124 360,145 378,175 395,200 402,195 404,183 418,179 432,180 437,184 437,196 428,205 412,211 404,211 406,222 412,232 420,242 437,256 437,387 0,387",
3:"0,128 15,105 35,80 50,68 80,52 120,40 170,30 215,26 260,28 300,33 335,42 360,52 378,65 395,90 410,115 425,140 437,165 437,387 0,387",
4:"0,62 15,45 40,28 80,15 130,7 200,3 270,3 320,6 360,14 390,25 415,40 430,55 437,70 437,387 0,387",
5:"0,0 300,0 340,6 380,18 410,34 437,60 437,387 0,387",
6:"0,0 310,0 350,8 390,22 420,40 437,55 437,387 0,387",
7:"0,0 340,0 390,12 420,30 437,50 437,387 0,387",
8:"0,0 370,0 400,20 437,45 437,387 0,387"}
# edge fade (side, top, bottom, corner radius) in source pixels, only where the art is cut by the GIF canvas
F={2:(28,0,60,90),3:(42,14,80,120),4:(46,24,80,130),5:(52,40,80,140),6:(52,40,80,140),7:(56,48,80,150),8:(60,52,80,160)}
H,W=388,438
SRC=[f.convert('RGB') for f in ImageSequence.Iterator(Image.open(os.path.join(HERE,'welcome_source.gif')))]
assert len(SRC)==len(P)
for i in range(len(SRC)):
    rgb=np.array(SRC[i])
    poly=np.array([list(map(int,p.split(','))) for p in P[i].split()])
    S=4; m=np.zeros((H*S,W*S),np.uint8)
    cv2.fillPoly(m,[(poly*S+S//2).astype(np.int32)],255)
    hard=(cv2.resize(m,(W,H),interpolation=cv2.INTER_AREA)>127).astype(np.uint8)
    if i<=4:
        band=2 if i<2 else 5
        k=np.ones((band*2+1,)*2,np.uint8)
        gm=np.full((H,W),cv2.GC_BGD,np.uint8)
        gm[cv2.dilate(hard,k)>0]=cv2.GC_PR_BGD; gm[hard>0]=cv2.GC_PR_FGD
        gm[cv2.erode(hard,k,borderType=cv2.BORDER_REPLICATE)>0]=cv2.GC_FGD
        cv2.setRNGSeed(1)
        cv2.grabCut(rgb[:,:,::-1].copy(),gm,None,np.zeros((1,65)),np.zeros((1,65)),6,cv2.GC_INIT_WITH_MASK)
        r=((gm==cv2.GC_FGD)|(gm==cv2.GC_PR_FGD)).astype(np.uint8)
        r=cv2.morphologyEx(cv2.morphologyEx(r,cv2.MORPH_OPEN,np.ones((3,3),np.uint8)),cv2.MORPH_CLOSE,np.ones((3,3),np.uint8))
        n,l,st,_=cv2.connectedComponentsWithStats(r); r=(l==1+st[1:,4].argmax()).astype(np.uint8)
        a=cv2.GaussianBlur(r.astype(np.float32),(0,0),0.7)
    else:
        a=cv2.GaussianBlur(cv2.resize(m,(W,H),interpolation=cv2.INTER_AREA).astype(np.float32)/255,(0,0),5,borderType=cv2.BORDER_REPLICATE)
    if i in F:
        s,t,b,R=F[i]
        y,x=np.mgrid[0:H,0:W].astype(np.float32)+0.5
        ss=lambda v:(lambda u:u*u*(3-2*u))(np.clip(v,0,1))
        top=0 if t else -300
        hx=W/2; y0,y1=top,H; hy=(y1-y0)/2
        px=x-hx; py=y-(y0+y1)/2
        qx=np.abs(px)-(hx-R); qy=np.abs(py)-(hy-R)
        ox=np.maximum(qx,0); oy=np.maximum(qy,0)
        sd=np.hypot(ox,oy)+np.minimum(np.maximum(qx,qy),0)-R
        # per-side softness, blended continuously around the corners
        wy=np.where(py>0,b,t if t else s)
        k=np.clip(0.5+((qy-qx)/(2*R)),0,1); k=k*k*(3-2*k)
        w=s*(1-k)+wy*k
        e=ss(-sd/w)
        a=a*e
    out=np.dstack([rgb,(np.clip(a,0,1)*255+.5).astype(np.uint8)])
    out[out[:,:,3]==0,:3]=0
    img = Image.fromarray(out, "RGBA")
    name = f"welcome_drive_{i}"
    img.save(os.path.join(ANDROID, name + ".webp"), lossless=True, exact=True)
    folder = os.path.join(IOS, name + ".imageset")
    os.makedirs(folder, exist_ok=True)
    img.save(os.path.join(folder, name + ".png"), optimize=True)
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": name + ".png", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)
print("ok")
