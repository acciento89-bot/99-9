"""Local CI artifact guards only. All AAB modules are retained; no signing or network code."""
import argparse,base64,hashlib,io,json,os,pathlib,re,stat,zipfile,xml.etree.ElementTree as ET
SIG=re.compile(r'META-INF/(?:MANIFEST\.MF|[^/]+\.(?:SF|RSA|DSA|EC)|SIG-[^/]+)$',re.I)
FIELDS=('GITHUB_REPOSITORY','GITHUB_REPOSITORY_ID','GITHUB_SHA','GITHUB_RUN_ID','GITHUB_RUN_ATTEMPT','GITHUB_EVENT_NAME','GITHUB_REF','GITHUB_WORKFLOW_REF','RELEASE_WORKFLOW','PACKAGE_NAME','VERSION_CODE','VERSION_NAME')
def check(value,reason):
 if not value:raise ValueError(reason)
def sha(raw):return hashlib.sha256(raw).hexdigest()
def members(raw):
 check(0<len(raw)<768*1024*1024,'Archive size')
 with zipfile.ZipFile(io.BytesIO(raw)) as z:
  out={};seen=set();total=0
  for item in z.infolist():
   name=item.filename.rstrip('/') if item.is_dir() else item.filename;p=pathlib.PurePosixPath(name)
   check(name and str(p)==name and not p.is_absolute() and '\\' not in name and all(x not in ('','.','..') for x in name.split('/')) and name.casefold() not in seen,'Unsafe/duplicate ZIP member');seen.add(name.casefold())
   check(stat.S_IFMT(item.external_attr>>16) in (0,stat.S_IFREG,stat.S_IFDIR) and not item.flag_bits&1,'Special/encrypted ZIP member')
   total+=item.file_size;check(item.file_size<512*1024*1024 and total<1536*1024*1024,'Expanded size')
   if not item.is_dir():out[name]=z.read(item)
  return out
def payload(raw):
 files=members(raw)
 check('base/manifest/AndroidManifest.xml' in files and 'assetPackInstallTime/manifest/AndroidManifest.xml' in files,'Missing base/install-time module')
 check(any(n.startswith('assetPackInstallTime/assets/') for n in files),'Missing install-time assets')
 return {n:sha(value) for n,value in sorted(files.items()) if not SIG.fullmatch(n)}
def equal_payload(before,after):check(payload(before)==payload(after),'Changed complete AAB module payload')
def strict_json(raw):
 def pairs(values):
  out={}
  for k,v in values:check(k not in out,'Duplicate JSON key');out[k]=v
  return out
 return json.loads(raw,object_pairs_hook=pairs,parse_constant=lambda _:check(False,'Nonfinite JSON'))
def write(path,value):
 with pathlib.Path(path).open('x') as f:json.dump(value,f,sort_keys=True,indent=2);f.write('\n')
def context():
 values={k:os.environ[k] for k in FIELDS if k not in ('VERSION_CODE','VERSION_NAME')}
 values.update(VERSION_CODE=os.environ['EXPECTED_VERSION_CODE'],VERSION_NAME=os.environ['EXPECTED_VERSION_NAME']);return values
def require_manual(ctx):
 check(set(ctx)==set(FIELDS),'Source context fields')
 check(re.fullmatch('[a-f0-9]{40}',ctx['GITHUB_SHA']) is not None,'Source SHA')
 check(all(re.fullmatch('[1-9][0-9]*',ctx[k]) for k in ('GITHUB_REPOSITORY_ID','GITHUB_RUN_ID','VERSION_CODE')),'Numeric context')
 check(ctx['GITHUB_EVENT_NAME']=='workflow_dispatch' and ctx['GITHUB_REF']=='refs/heads/main' and ctx['GITHUB_RUN_ATTEMPT']=='1','Manual main first attempt required')
 check(ctx['GITHUB_WORKFLOW_REF']==ctx['GITHUB_REPOSITORY']+'/'+ctx['RELEASE_WORKFLOW']+'@refs/heads/main','Exact workflow/repository path')
def prepare(source,out,ctx):
 check(set(ctx)==set(FIELDS),'Source context fields');raw=pathlib.Path(source).read_bytes();expected=payload(raw);out=pathlib.Path(out);out.mkdir()
 with zipfile.ZipFile(io.BytesIO(raw)) as src,zipfile.ZipFile(out/'app.aab','x') as dest:
  for info in src.infolist():
   if not info.is_dir() and not SIG.fullmatch(info.filename):dest.writestr(info,src.read(info))
 unsigned=(out/'app.aab').read_bytes();equal_payload(raw,unsigned);check(not any(SIG.fullmatch(n) for n in members(unsigned)),'Unsigned normalization failed')
 write(out/'payload.json',expected);write(out/'source.json',{'schema':1,'context':ctx,'rawBuildSha256':sha(raw),'unsignedSha256':sha(unsigned),'fullModulePayloadSha256':sha(json.dumps(expected,sort_keys=True,separators=(',',':')).encode())})
 (out/'source-commit.txt').write_text(ctx['GITHUB_SHA']+'\n')
def recheck(folder,ctx):
 require_manual(ctx);folder=pathlib.Path(folder);source=strict_json((folder/'source.json').read_bytes());check(source['schema']==1 and source['context']==ctx,'Exact source/run/event/workflow context differs')
 raw=(folder/'app.aab').read_bytes();p=payload(raw)
 check(not any(SIG.fullmatch(n) for n in members(raw)),'Input already signed')
 check(sha(raw)==source['unsignedSha256'] and strict_json((folder/'payload.json').read_bytes())==p and sha(json.dumps(p,sort_keys=True,separators=(',',':')).encode())==source['fullModulePayloadSha256'],'Unsigned hash/full-module digest differs')
 check((folder/'source-commit.txt').read_text()==ctx['GITHUB_SHA']+'\n','Source commit file differs');return source

def unpack(raw,meta,digest,artifact_id,name,ctx,out):
 require_manual(ctx);digest=digest.removeprefix('sha256:');check(re.fullmatch('[a-f0-9]{64}',digest) and sha(raw)==digest,'Actual artifact archive digest differs')
 check(meta['id']==artifact_id and meta['name']==name and meta['digest']=='sha256:'+digest and meta['expired'] is False,'Official immutable artifact metadata differs')
 run=meta['workflow_run'];check(run['id']==int(ctx['GITHUB_RUN_ID']) and run['repository_id']==run['head_repository_id']==int(ctx['GITHUB_REPOSITORY_ID']) and run['head_sha']==ctx['GITHUB_SHA'] and run['head_branch']=='main','Artifact source run/repository/SHA differs')
 files=members(raw);check(set(files)=={'app.aab','payload.json','source.json','source-commit.txt'},'Exact unsigned artifact members required')
 out=pathlib.Path(out);out.mkdir()
 for name,value in files.items():
  with (out/name).open('xb') as f:f.write(value)
 recheck(out,ctx);write(out/'transfer.json',{'artifactId':artifact_id,'artifactName':meta['name'],'artifactArchiveSha256':digest,'sourceRunId':run['id']})
def signature_coverage(raw):
 files=members(raw);mf=[n for n in files if n.upper()=='META-INF/MANIFEST.MF'];sf=[n for n in files if re.fullmatch('META-INF/[^/]+\\.SF',n,re.I)];blocks=[n for n in files if re.fullmatch('META-INF/[^/]+\\.(RSA|DSA|EC)',n,re.I)]
 check(len(mf)==len(sf)==len(blocks)==1 and sf[0].rsplit('.',1)[0].lower()==blocks[0].rsplit('.',1)[0].lower(),'Exactly one complete JAR signer')
 def sections(value):
  lines=[]
  for line in value.replace(b'\r\n',b'\n').split(b'\n'):
   if line.startswith(b' '):check(bool(lines) and bool(lines[-1]),'Manifest continuation');lines[-1]+=line[1:]
   else:lines.append(line)
  out=[];current={}
  for line in lines+[b'']:
   if not line:
    if current:out.append(current);current={}
   else:
    check(b': ' in line,'Manifest header');k,v=line.split(b': ',1);k=k.decode().lower();check(k not in current,'Duplicate manifest header');current[k]=v.decode()
  return out
 headers=sections(files[mf[0]]);check(headers and headers[0].get('manifest-version')=='1.0','JAR manifest version')
 records={}
 for h in headers[1:]:check(h.get('name') and h['name'] not in records,'Manifest duplicate name');records[h['name']]=h
 check(set(records)==set(payload(raw)),'Signature manifest must cover every module payload entry')
 for name,h in records.items():check(base64.b64decode(h.get('sha-256-digest',''),validate=True).hex()==sha(files[name]),'Manifest entry digest')
 sfheaders=sections(files[sf[0]]);check(sfheaders and base64.b64decode(sfheaders[0].get('sha-256-digest-manifest',''),validate=True).hex()==sha(files[mf[0]]),'Whole signed manifest digest')
def finish(folder,signed,ctx):
 source=recheck(folder,ctx);raw=pathlib.Path(signed).read_bytes();equal_payload((pathlib.Path(folder)/'app.aab').read_bytes(),raw);signature_coverage(raw)
 dest=pathlib.Path(signed).parent;transfer=strict_json((pathlib.Path(folder)/'transfer.json').read_bytes())
 write(dest/'provenance.json',{'context':ctx,'source':source,'transfer':transfer,'signedAabSha256':sha(raw),'publicCertificateSha1':os.environ['CENTRAL_SHA1'],'publicCertificateSha256':os.environ['CENTRAL_SHA256'],'allModulePayloadUnchanged':True})
 write(dest/'payload.json',payload(raw));(dest/'SHA256SUMS').write_text(sha(raw)+'  '+pathlib.Path(signed).name+'\n')
def install_time(xml,package):
 root=ET.fromstring(xml);dist='{http://schemas.android.com/apk/distribution}'
 check(root.tag=='manifest' and root.get('package')==package and root.get('split')=='assetPackInstallTime','Exact asset-pack manifest identity')
 module=root.find(dist+'module');check(module is not None and module.get(dist+'type')=='asset-pack','Actual asset pack module')
 delivery=module.find(dist+'delivery');check(delivery is not None and [x.tag for x in delivery]==[dist+'install-time'],'Actual install-time delivery required')
 fusing=module.find(dist+'fusing');check(fusing is not None and fusing.get(dist+'include')=='true','Universal APK must fuse the actual asset pack')
def main():
 a=argparse.ArgumentParser();a.add_argument('mode',choices=['prepare','unpack','recheck','finish','pack']);a.add_argument('--input',type=pathlib.Path);a.add_argument('--out',type=pathlib.Path);a.add_argument('--archive',type=pathlib.Path);a.add_argument('--metadata',type=pathlib.Path);a.add_argument('--digest');a.add_argument('--artifact-id',type=int);a.add_argument('--artifact-name');a.add_argument('--signed',type=pathlib.Path);v=a.parse_args();ctx=context()
 if v.mode=='pack':install_time(v.input.read_bytes(),ctx['PACKAGE_NAME'])
 elif v.mode=='prepare':prepare(v.input,v.out,ctx)
 elif v.mode=='unpack':unpack(v.archive.read_bytes(),strict_json(v.metadata.read_bytes()),v.digest,v.artifact_id,v.artifact_name,ctx,v.out)
 elif v.mode=='recheck':recheck(v.input,ctx)
 else:finish(v.input,v.signed,ctx)
if __name__=='__main__':main()
