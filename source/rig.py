import base64, zlib, json, struct, hashlib
from pathlib import Path
import numpy as np
from scipy.spatial.transform import Rotation as R
base=Path(__file__).resolve().parents[1]
src=base/'source/survivor.glb'
assert hashlib.sha256(src.read_bytes()).hexdigest()=='e61a13a181b75213b94ae285fa6a5d6ead5ba25db092b65cc23eba3b7399eff1'
lines=[x.split() for x in (base/'source/motion_v2.txt').read_text().splitlines() if x.strip()]
def decode(s):return zlib.decompress(base64.b64decode(s))
rest=np.frombuffer(decode(lines[0][1]),dtype='<f4').reshape(22,7)
bones=['Hips','Spine','Spine1','Spine2','Neck','Head','LeftShoulder','LeftArm','LeftForeArm','LeftHand','LeftUpLeg','LeftLeg','LeftFoot','LeftToeBase','RightShoulder','RightArm','RightForeArm','RightHand','RightUpLeg','RightLeg','RightFoot','RightToeBase']
parents=[-1,0,1,2,3,4,3,6,7,8,0,10,11,12,3,14,15,16,0,18,19,20]
P={'Hips':(0,.53,.015),'Spine':(0,.60,.01),'Spine1':(0,.68,.005),'Spine2':(0,.76,.005),'Neck':(0,.83,.018),'Head':(0,.89,.025),'HeadTop_End':(0,.99,.025)}
nxt={'Hips':'Spine','Spine':'Spine1','Spine1':'Spine2','Spine2':'Neck','Neck':'Head','Head':'HeadTop_End'}
for side,sign in [('Left',1),('Right',-1)]:
 for k,v in {'Shoulder':(.045,.79,.005),'Arm':(.105,.785,.002),'ForeArm':(.155,.638,.014),'Hand':(.155,.525,.054),'HandEnd':(.16,.447,.067),'UpLeg':(.055,.52,.015),'Leg':(.072,.275,.005),'Foot':(.106,.061,-.015),'ToeBase':(.11,.029,.066),'Toe_End':(.11,.027,.105)}.items():P[side+k]=(v[0]*sign,v[1],v[2])
 for a,b in [('Shoulder','Arm'),('Arm','ForeArm'),('ForeArm','Hand'),('Hand','HandEnd'),('UpLeg','Leg'),('Leg','Foot'),('Foot','ToeBase'),('ToeBase','Toe_End')]:nxt[side+a]=side+b
P={k:np.array(v)*1.8 for k,v in P.items()}
with src.open('rb') as f:
 f.read(12);l,_=struct.unpack('<II',f.read(8));j=json.loads(f.read(l));l,_=struct.unpack('<II',f.read(8));buf=bytearray(f.read(l))
def acc(a,ctype=5126,typ='SCALAR',target=None,bounds=False):
 a=np.asarray(a,dtype={5126:'<f4',5123:'<u2'}[ctype]);off=len(buf);buf.extend(a.tobytes());buf.extend(b'\0'*((-len(buf))%4));v={'buffer':0,'byteOffset':off,'byteLength':a.nbytes}
 if target:v['target']=target
 j['bufferViews'].append(v);d={'bufferView':len(j['bufferViews'])-1,'componentType':ctype,'count':len(a),'type':typ}
 if bounds:d.update(min=np.min(a,axis=0).reshape(-1).tolist(),max=np.max(a,axis=0).reshape(-1).tolist())
 j['accessors'].append(d);return len(j['accessors'])-1
def get(i):
 a=j['accessors'][i];v=j['bufferViews'][a['bufferView']];return np.frombuffer(buf,dtype='<f4',count=a['count']*3,offset=v.get('byteOffset',0)+a.get('byteOffset',0)).copy().reshape(-1,3)
j['materials']=[{'name':'Survivor Gray','pbrMetallicRoughness':{'baseColorFactor':[.52,.52,.52,1],'metallicFactor':0,'roughnessFactor':.86}}]; mi={k:0 for k in ['denim','shirt','skin','boot','bag','dark','metal','hair']}; j.pop('textures',None);j.pop('images',None);j.pop('samplers',None)
L=['LeftUpLeg','LeftLeg','LeftFoot','LeftToeBase'];RR=['RightUpLeg','RightLeg','RightFoot','RightToeBase'];LA=['LeftShoulder','LeftArm','LeftForeArm','LeftHand'];RA=['RightShoulder','RightArm','RightForeArm','RightHand'];torso=['Hips','Spine','Spine1','Spine2','Neck'];head=['Neck','Head']
parts={0:(L+['Hips'],'denim'),1:(RR+['Hips'],'denim'),2:(torso,'shirt'),3:(head,'skin'),4:(L[2:],'boot'),5:(RA+['Spine2'],'shirt'),6:(RR[2:],'boot'),7:(LA+['Spine2'],'shirt'),8:(torso,'bag'),9:(RA[2:],'skin'),10:(LA[2:],'skin'),11:(['RightUpLeg'],'bag'),12:(torso,'dark'),13:(LA[1:],'skin'),14:(RA[1:],'skin'),15:(['Spine2'],'bag'),16:(['Spine'],'bag'),17:(['Spine1'],'bag'),18:(['Spine1'],'bag'),19:(['RightUpLeg'],'bag'),20:(head,'skin'),21:(RR+['Hips'],'denim'),22:(torso,'bag'),23:(['Head'],'hair'),24:(['Spine1'],'bag'),25:(torso,'bag'),26:(LA[2:],'metal'),27:(head,'hair'),28:(torso,'shirt'),29:(torso,'shirt'),30:(['Head'],'skin'),31:(torso,'shirt'),32:(['Spine1'],'metal'),33:(torso,'bag'),34:(['RightUpLeg'],'metal')}
# All overlapping garment pieces use the same anatomical weight field.
# This avoids disconnected cuffs, boot seams and pelvis patches.
def smooth(x,a,b):
 t=np.clip((x-a)/(b-a),0,1);return t*t*(3-2*t)
def field(v,i):
 x,y,z=(v/1.8).T
 W=np.zeros((len(v),len(bones)))
 def set_weight(n,w):W[:,bones.index(n)]+=w
 def rigid(n):set_weight(n,1.)
 def arm(side):
  wrist=smooth(y,.515,.553);elbow=smooth(y,.606,.672);shoulder=smooth(y,.755,.817)
  set_weight(side+'Hand',1-wrist);set_weight(side+'ForeArm',wrist*(1-elbow));set_weight(side+'Arm',wrist*elbow*(1-shoulder));set_weight(side+'Shoulder',wrist*elbow*shoulder)
 def leg(side,factor=1.):
  hip=smooth(y,.447,.551);knee=smooth(y,.238,.310);ankle=smooth(y,.047,.105);toe=smooth(z,.034,.083)
  set_weight('Hips',factor*hip);set_weight(side+'UpLeg',factor*(1-hip)*knee)
  set_weight(side+'Leg',factor*(1-hip)*(1-knee)*ankle);set_weight(side+'Foot',factor*(1-hip)*(1-knee)*(1-ankle)*(1-toe));set_weight(side+'ToeBase',factor*(1-hip)*(1-knee)*(1-ankle)*toe)
 def trunk():
  a=smooth(y,.545,.625);b=smooth(y,.62,.705);c=smooth(y,.70,.775);d=smooth(y,.80,.865)
  set_weight('Hips',1-a);set_weight('Spine',a*(1-b));set_weight('Spine1',a*b*(1-c));set_weight('Spine2',a*b*c*(1-d));set_weight('Neck',a*b*c*d)
 if i in (0,4):leg('Left')
 elif i in (1,6,11,19,34):leg('Right')
 elif i==21:
  left=smooth(x,-.023,.023);leg('Left',left);leg('Right',1-left)
 elif i in (7,10,13,26):arm('Left')
 elif i in (5,9,14):arm('Right')
 elif i in (3,23,27,30):rigid('Head')
 elif i==20:
  a=smooth(y,.838,.883);set_weight('Neck',1-a);set_weight('Head',a)
 elif i in (8,15,16,17,18,24,32):rigid('Spine2')
 else:trunk()
 idx=np.argsort(-W,axis=1)[:,:4];vals=np.take_along_axis(W,idx,axis=1);vals/=vals.sum(axis=1,keepdims=True)
 assert np.isfinite(vals).all() and np.max(np.abs(vals.sum(axis=1)-1))<1e-6
 return idx,vals
boot_data=[]
for i,m in enumerate(j['meshes']):
 p=m['primitives'][0];ids=p['attributes'];v=get(ids['POSITION'])*1.8;ids['POSITION']=acc(v,typ='VEC3',target=34962,bounds=True);p['material']=0;ids.pop('COLOR_0',None)
 ji,vals=field(v,i)
 ids['JOINTS_0']=acc(ji,5123,'VEC4',34962);ids['WEIGHTS_0']=acc(vals,5126,'VEC4',34962)
 if i in (4,6):
  mask=v[:,1]<.055;boot_data.append((v[mask],ji[mask],vals[mask]))
offset=len(j['nodes']);global_mats=[];inv=[]
for i,n in enumerate(bones):
 t,q=rest[i,:3],rest[i,3:];q=q/np.linalg.norm(q);mat=np.eye(4);mat[:3,:3]=R.from_quat(q).as_matrix();mat[:3,3]=t
 g=global_mats[parents[i]]@mat if parents[i]>=0 else mat;global_mats.append(g);inv.append(np.linalg.inv(g).T.reshape(-1))
 node={'name':n,'translation':t.tolist(),'rotation':q.tolist()};children=[offset+k for k,p in enumerate(parents) if p==i]
 if children:node['children']=children
 j['nodes'].append(node)
j['nodes'][0]['children'].append(offset)
j['skins']=[{'name':'SurvivorRig','joints':list(range(offset,offset+22)),'skeleton':offset,'inverseBindMatrices':acc(inv,typ='MAT4')}]
for n in j['nodes'][1:offset]:
 if 'mesh' in n:n['skin']=0
# Original 30 Hz motion samples. No generated frames, pose overrides or forced loop endpoints.
inv_mats=np.array(inv).reshape(-1,4,4).transpose(0,2,1)
verts=np.concatenate([x[0] for x in boot_data]); joint_ids=np.concatenate([x[1] for x in boot_data]); weights=np.concatenate([x[2] for x in boot_data]); vh=np.c_[verts,np.ones(len(verts))]
local_sole=np.einsum('nkij,nj->nki',inv_mats[joint_ids],vh)
clips={}; floors={}; scale=1.8/178.55
for label in ('idle','walk','run','jump','run_jump'):
 _,count,dur,encoded=(base/'source/native'/f'{label}.txt').read_text().split()
 count=int(count); dur=float(dur); raw=decode(encoded)
 q0=R.from_quat(np.frombuffer(raw,dtype='<f4',count=88).reshape(22,4)); p0=np.frombuffer(raw,dtype='<f4',count=3,offset=352)
 dd=np.frombuffer(raw,dtype='i1',offset=364,count=69*count).astype(np.int32); mask=dd==-128
 dd[mask]=np.frombuffer(raw,dtype='<i2',offset=364+69*count)
 d=np.cumsum(np.cumsum(dd.reshape(69,count),axis=1),axis=1)
 rv=np.deg2rad(d[:66].reshape(22,3,count).transpose(2,0,1)/4.)
 qs=np.stack([(q0*R.from_rotvec(x)).as_quat() for x in rv]).transpose(1,0,2)
 p=p0+d[66:].T/10.; times=np.linspace(0,dur,count)
 hips=np.tile(rest[0,:3],(count,1)); hips[:,0]+=(p[:,0]-p[0,0])*scale; hips[:,1]+=(p[:,1]-99.7919388)*scale; hips[:,2]+=(p[:,2]-p[0,2])*scale
 if label in ('walk','run','run_jump'):
  hips[:,2]-=np.linspace(0,(p[-1,2]-p[0,2])*scale,count)
 sole=[]
 for k in range(count):
  mats=[]
  for i in range(22):
   m=np.eye(4);m[:3,:3]=R.from_quat(qs[i,k]).as_matrix();m[:3,3]=hips[k] if i==0 else rest[i,:3];mats.append(mats[parents[i]]@m if parents[i]>=0 else m)
  transformed=np.einsum('nkij,nkj->nki',np.asarray(mats)[joint_ids],local_sole)
  sole.append(float(np.min(np.sum(transformed[:,:,1]*weights,axis=1))))
 floors[label]=np.asarray(sole); clips[label]=(times,qs,hips)
 print(label,count,'duration',dur,'sole range',np.round(np.percentile(sole,[0,10,50,90,100]),3))
# Add all twelve original FBX clips from the user's archive.
from pack_fbx import sample_pack
for label,times,qs,hips in sample_pack(base/'source/locomotion',bones,parents,rest):
 sole=[]
 for k in range(len(times)):
  mats=[]
  for i in range(22):
   m=np.eye(4);m[:3,:3]=R.from_quat(qs[i,k]).as_matrix();m[:3,3]=hips[k] if i==0 else rest[i,:3];mats.append(mats[parents[i]]@m if parents[i]>=0 else m)
  transformed=np.einsum('nkij,nkj->nki',np.asarray(mats)[joint_ids],local_sole)
  sole.append(float(np.min(np.sum(transformed[:,:,1]*weights,axis=1))))
 floors[label]=np.asarray(sole);clips[label]=(times,qs,hips)
 print(label,len(times),'duration',times[-1])
j['animations']=[]
profiles={}
turns={}
jump_meta={}
loop_names={'idle','walk','run','pack_idle','pack_walk','pack_run','pack_left_walk','pack_right_walk','pack_left_run','pack_right_run'}
for label,(times,qs,hips) in clips.items():
 floor_ref=float(np.percentile(floors[label],10));hips[:,1]+=.006-floor_ref
 if label in ('jump','run_jump','pack_jump'):
  profile=np.maximum(0,floors[label]-floor_ref-.035);profile[0]=profile[-1]=0
  # Remove the airborne part of root motion. CharacterBody3D supplies it once, using gravity.
  peak=int(np.argmax(profile));cut=max(.035,float(profile[peak])*.10);lo=peak;hi=peak
  while lo>0 and profile[lo]>cut:lo-=1
  while hi<len(profile)-1 and profile[hi]>cut:hi+=1
  lo=max(0,min(lo,peak-1));hi=min(len(profile)-1,max(hi,peak+1))
  arc=np.zeros(len(times));arc[lo:hi+1]=profile[lo:hi+1];arc[lo]=arc[hi]=0.
  hips[:,1]-=arc
  jump_meta[label]=[float(times[lo]),float(times[hi]),float(np.max(arc))]
  profiles[label]=np.round(profile,5).tolist()
 if label in ('pack_left_90','pack_right_90','pack_left_180','pack_right_180'):
  # Extract heading from pelvis quaternion; apply it exactly once on the body in Godot.
  root=R.from_quat(qs[0]);relative=root*root[0].inv();forward=relative.apply(np.tile([0.,0.,1.],(len(times),1)))
  yaw=np.unwrap(np.arctan2(forward[:,0],forward[:,2]))
  heading=R.from_rotvec(np.c_[np.zeros(len(yaw)),yaw,np.zeros(len(yaw))])
  qs[0]=(heading.inv()*root).as_quat()
  turns[label]=np.round(yaw,6).tolist()
  hips[:,0]=rest[0,0];hips[:,2]=rest[0,2]
 if label in loop_names:
  # Close only the small difference at the loop seam over the last 3 samples.
  from scipy.spatial.transform import Slerp
  for i in range(22):
   for k in range(1,min(4,len(times))):
    t=(4-k)/3.
    t=min(1.,t)
    qs[i,-k]=Slerp([0.,1.],R.from_quat([qs[i,-k],qs[i,0]]))([t]).as_quat()[0]
  for k in range(1,min(4,len(times))):
   t=min(1.,(4-k)/3.);hips[-k]=hips[-k]*(1-t)+hips[0]*t
 ta=acc(times,bounds=True);a={'name':label,'samplers':[],'channels':[]}
 for i,q in enumerate(qs):
  for k in range(1,len(q)):
   if q[k]@q[k-1]<0:q[k]*=-1
  a['channels'].append({'sampler':i,'target':{'node':offset+i,'path':'rotation'}});a['samplers'].append({'input':ta,'output':acc(q,typ='VEC4'),'interpolation':'LINEAR'})
 a['channels'].append({'sampler':22,'target':{'node':offset,'path':'translation'}});a['samplers'].append({'input':ta,'output':acc(hips,typ='VEC3'),'interpolation':'LINEAR'});j['animations'].append(a)
 assert len(times)==round(times[-1]*30)+1 and np.isfinite(qs).all() and np.isfinite(hips).all()
profile_file=base/'assets/jump_profiles.gd';profile_file.parent.mkdir(exist_ok=True)
profile_file.write_text('extends RefCounted\nconst JUMPS = '+json.dumps(jump_meta)+'\nconst TURNS = '+json.dumps(turns)+'\n')
print('Jump phases:',jump_meta)
j.pop('extensionsUsed',None);j.pop('extensionsRequired',None);j['buffers'][0]['byteLength']=len(buf)
data=json.dumps(j,separators=(',',':')).encode();data+=b' '*((-len(data))%4)
out=base/'assets/survivor_rig.glb';out.parent.mkdir(exist_ok=True)
out.write_bytes(struct.pack('<4sII',b'glTF',2,12+8+len(data)+8+len(buf))+struct.pack('<I4s',len(data),b'JSON')+data+struct.pack('<I4s',len(buf),b'BIN\0')+buf)
print('Rig generated:',out,len(j['animations']),'clips')
