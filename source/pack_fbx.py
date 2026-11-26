"""Read the supplied Mixamo FBX binary curves without quantization."""
import struct,zlib
from pathlib import Path
import numpy as np
from scipy.spatial.transform import Rotation as R

def read(path):
 with open(path,'rb') as f:
  f.seek(23);ver=struct.unpack('<I',f.read(4))[0]
  wide=ver>=7500;fmt='<QQQB' if wide else '<IIIB';size=25 if wide else 13
  def node():
   end,n,plen,nlen=struct.unpack(fmt,f.read(size))
   if not end:return None
   name=f.read(nlen).decode();vals=[]
   for _ in range(n):
    t=f.read(1).decode()
    if t in 'YCILFD':
     fm={'Y':'h','C':'?','I':'i','L':'q','F':'f','D':'d'}[t];vals.append(struct.unpack('<'+fm,f.read(struct.calcsize(fm)))[0])
    elif t in 'SR':
     l=struct.unpack('<I',f.read(4))[0];b=f.read(l);vals.append(b.decode(errors='replace') if t=='S' else b)
    else:
     l,e,s=struct.unpack('<III',f.read(12));b=f.read(s);b=zlib.decompress(b) if e else b
     vals.append(np.frombuffer(b,dtype={'f':'<f4','d':'<f8','i':'<i4','l':'<i8','b':'u1','c':'u1'}[t]))
   cs=[]
   while f.tell()<end-size:
    x=node()
    if x is None:break
    cs.append(x)
   f.seek(end);return name,vals,cs
  out=[]
  while True:
   n=node()
   if n is None:break
   out.append(n)
  return out

def load(path):
 ns=read(path);objs=next(x[2] for x in ns if x[0]=='Objects');con=[x[1] for x in next(x[2] for x in ns if x[0]=='Connections')]
 models={x[1][0]:x for x in objs if x[0]=='Model' and x[1][-1]=='LimbNode'}
 names={i:x[1][1].split('\x00')[0].split(':')[-1] for i,x in models.items()}
 props={names[i]:{y[1][0]:y[1][4:] for y in next(z[2] for z in x[2] if z[0]=='Properties70')} for i,x in models.items()}
 parent={names[c[1]]:names[c[2]] for c in con if c[0]=='OO' and c[1] in models and c[2] in models}
 cn={x[1][0]:x for x in objs if x[0]=='AnimationCurveNode'}
 cv={x[1][0]:{y[0]:y[1][0] for y in x[2] if y[1]} for x in objs if x[0]=='AnimationCurve'}
 mapping={c[1]:(names[c[2]],c[3]) for c in con if c[0]=='OP' and c[1] in cn and c[2] in models};curves={}
 for c in con:
  if c[0]=='OP' and c[1] in cv and c[2] in mapping:
   a,b=mapping[c[2]];curves[a,b,c[3][-1]]=cv[c[1]]
 def prop(n,k,d):return np.array(props[n].get(k,d),float)
 def ro(n,k):return R.from_euler('xyz',prop(n,k,[0,0,0]),degrees=True)
 def pose(ts=None):
  g={};pos={}
  def visit(n):
   if n in g:return
   par=parent.get(n)
   if par:visit(par)
   t=prop(n,'Lcl Translation',[0,0,0]);e=prop(n,'Lcl Rotation',[0,0,0])
   if ts is not None:
    for k,v in [('Lcl Translation',t),('Lcl Rotation',e)]:
     for i,ax in enumerate('XYZ'):
      q=curves.get((n,k,ax))
      if q is not None:v[i]=np.interp(ts,q['KeyTime']/46186158000.,q['KeyValueFloat'])
   r=ro(n,'PreRotation')*R.from_euler('xyz',e,degrees=True)*ro(n,'PostRotation').inv()
   g[n]=g[par]*r if par else r;pos[n]=pos[par]+g[par].apply(t) if par else t
  for n in props:visit(n)
  return g,pos
 dur=max(float(q['KeyTime'][-1])/46186158000 for q in curves.values() if len(q['KeyTime']))
 return pose,dur

PACK={'pack_idle':'idle.fbx','pack_walk':'walking.fbx','pack_run':'running.fbx','pack_jump':'jump.fbx','pack_left_walk':'left strafe walking.fbx','pack_right_walk':'right strafe walking.fbx','pack_left_run':'left strafe.fbx','pack_right_run':'right strafe.fbx','pack_left_90':'left turn 90.fbx','pack_right_90':'right turn 90.fbx','pack_left_180':'left turn.fbx','pack_right_180':'right turn.fbx'}

def sample_pack(directory,bones,parents,rest):
 for label,filename in PACK.items():
  pose,dur=load(directory/filename);times=np.linspace(0,dur,round(dur*30)+1);qs=[];p=[]
  for t in times:
   g,pos=pose(t);qs.append([(g[bones[pa]].inv()*g[n] if pa>=0 else g[n]).as_quat() for n,pa in zip(bones,parents)]);p.append(pos['Hips'])
  qs=np.array(qs).transpose(1,0,2);p=np.asarray(p);hips=np.tile(rest[0,:3],(len(times),1));delta=(p-p[0])*1.8/178.55
  hips[:,0]+=delta[:,0];hips[:,2]+=delta[:,2];hips[:,1]+=(p[:,1]-99.7919388)*1.8/178.55
  # Extract only linear horizontal travel. Preserve original vertical motion, rotations and timing.
  if label in ('pack_walk','pack_run','pack_left_walk','pack_right_walk','pack_left_run','pack_right_run'):
   hips[:,0]-=np.linspace(0,delta[-1,0],len(times));hips[:,2]-=np.linspace(0,delta[-1,2],len(times))
  yield label,times,qs,hips
