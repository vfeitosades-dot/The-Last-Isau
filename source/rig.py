import base64, zlib, json, struct, hashlib
from pathlib import Path
import numpy as np
from scipy.spatial.transform import Rotation as R, RotationSpline
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
boot_data=[]
for i,m in enumerate(j['meshes']):
 p=m['primitives'][0];ids=p['attributes'];v=get(ids['POSITION'])*1.8;ids['POSITION']=acc(v,typ='VEC3',target=34962,bounds=True);names,col=parts[i];p['material']=mi[col];ids.pop('COLOR_0',None);ds=[]
 if i in (8,15,16,17,18,24,32):names=['Spine2']
 if i in (3,23,30):names=['Head']
 if i in (9,10):names=[names[-1]]
 for n in names:
  a=P[n];b=P[nxt[n]];d=b-a;u=np.clip((v-a)@d/(d@d),.13,.87);ds.append(np.linalg.norm(v-(a+u[:,None]*d),axis=1))
 ds=np.array(ds).T;w=np.exp(-((ds-ds.min(axis=1,keepdims=True))/.055)**2);idx=np.argsort(-w,axis=1)[:,:4];vals=np.take_along_axis(w,idx,axis=1);vals/=vals.sum(axis=1,keepdims=True);ji=np.array([bones.index(n) for n in names])[idx];pad=4-idx.shape[1]
 ids['JOINTS_0']=acc(np.pad(ji,((0,0),(0,pad))),5123,'VEC4',34962);ids['WEIGHTS_0']=acc(np.pad(vals,((0,0),(0,pad))),5126,'VEC4',34962)
 if i in (4,6):
  mask=v[:,1]<.055;boot_data.append((v[mask],np.pad(ji,((0,0),(0,pad)))[mask],np.pad(vals,((0,0),(0,pad)))[mask]))
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
# Reconstruct the five FBX clips at 60 Hz. Match actual deformed sole height.
from scipy.interpolate import PchipInterpolator
inv_mats=np.array(inv).reshape(-1,4,4).transpose(0,2,1)
verts=np.concatenate([x[0] for x in boot_data]); joint_ids=np.concatenate([x[1] for x in boot_data]); weights=np.concatenate([x[2] for x in boot_data]); vh=np.c_[verts,np.ones(len(verts))]
local_sole=np.einsum('nkij,nj->nki',inv_mats[joint_ids],vh)
j['animations']=[]
for label,count,dur,encoded in lines[1:]:
 count=int(count); dur=float(dur); raw=decode(encoded); xyz=np.frombuffer(raw,dtype='i1',count=22*count*3).reshape(22,count,3).astype(float)/127
 w=np.sqrt(np.maximum(0,1-(xyz**2).sum(axis=2))); qs=np.concatenate([xyz,w[:,:,None]],axis=2); qs/=np.linalg.norm(qs,axis=2,keepdims=True)
 motion=np.frombuffer(raw,dtype='<i2',offset=22*count*3).reshape(count,3)/1000.
 source_times=np.linspace(0,dur,count); times=np.linspace(0,dur,max(2,round(dur*60)+1)); motion=PchipInterpolator(source_times,motion,axis=0)(times)
 qs=np.stack([RotationSpline(source_times,R.from_quat(q))(times).as_quat() for q in qs]); hips=np.tile(rest[0,:3],(len(times),1)); hips[:,0]+=motion[:,0]; hips[:,2]+=motion[:,2]
 for k in range(len(times)):
  mats=[]
  for i in range(22):
   m=np.eye(4);m[:3,:3]=R.from_quat(qs[i,k]).as_matrix();m[:3,3]=hips[k] if i==0 else rest[i,:3];mats.append(mats[parents[i]]@m if parents[i]>=0 else m)
  transformed=np.einsum('nkij,nkj->nki',np.asarray(mats)[joint_ids],local_sole)
  foot_y=np.min(np.sum(transformed[:,:,1]*weights,axis=1));hips[k,1]+=motion[k,1]+.004-foot_y
 if label in ('idle','walk','run'):
  hips[-1]=hips[0];qs[:,-1]=qs[:,0]
 ta=acc(times,bounds=True);a={'name':label,'samplers':[],'channels':[]}
 for i,q in enumerate(qs):
  for k in range(1,len(q)):
   if q[k]@q[k-1]<0:q[k]*=-1
  a['channels'].append({'sampler':i,'target':{'node':offset+i,'path':'rotation'}});a['samplers'].append({'input':ta,'output':acc(q,typ='VEC4'),'interpolation':'LINEAR'})
 a['channels'].append({'sampler':22,'target':{'node':offset,'path':'translation'}});a['samplers'].append({'input':ta,'output':acc(hips,typ='VEC3'),'interpolation':'LINEAR'});j['animations'].append(a)
 print(label,len(times),'pelvis Y range',round(float(hips[:,1].min()),3),round(float(hips[:,1].max()),3))
j.pop('extensionsUsed',None);j.pop('extensionsRequired',None);j['buffers'][0]['byteLength']=len(buf)
data=json.dumps(j,separators=(',',':')).encode();data+=b' '*((-len(data))%4)
out=base/'assets/survivor_rig.glb';out.parent.mkdir(exist_ok=True)
out.write_bytes(struct.pack('<4sII',b'glTF',2,12+8+len(data)+8+len(buf))+struct.pack('<I4s',len(data),b'JSON')+data+struct.pack('<I4s',len(buf),b'BIN\0')+buf)
print('Rig generated:',out,len(j['animations']),'clips')
