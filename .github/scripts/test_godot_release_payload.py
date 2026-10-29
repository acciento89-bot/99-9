"""CPU-only adversarial tests of the actual full-module CI transfer verifier."""
import base64,hashlib,importlib.util,io,json,pathlib,tempfile,unittest,zipfile
HELPER=pathlib.Path(__file__).with_name('godot_release_payload.py')
spec=importlib.util.spec_from_file_location('guard',HELPER);g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
def bundle(files):
 b=io.BytesIO()
 with zipfile.ZipFile(b,'w') as z:
  for n,v in files.items():z.writestr(n,v)
 return b.getvalue()
BASE={'base/manifest/AndroidManifest.xml':b'm','base/dex/classes.dex':b'd','base/lib/arm64-v8a/lib.so':b'n','assetPackInstallTime/manifest/AndroidManifest.xml':b'p','assetPackInstallTime/assets/license/OFL.txt':b'original notice','assetPackInstallTime/assets/data.pck':b'game'}
CTX={'GITHUB_REPOSITORY':'owner/repo','GITHUB_REPOSITORY_ID':'9','GITHUB_SHA':'a'*40,'GITHUB_RUN_ID':'10','GITHUB_RUN_ATTEMPT':'1','GITHUB_EVENT_NAME':'workflow_dispatch','GITHUB_REF':'refs/heads/main','GITHUB_WORKFLOW_REF':'owner/repo/.github/workflows/android.yml@refs/heads/main','RELEASE_WORKFLOW':'.github/workflows/android.yml','PACKAGE_NAME':'de.own.game','VERSION_CODE':'7','VERSION_NAME':'1.2.0'}
class Guards(unittest.TestCase):
 def test_actual_install_time_manifest_and_fusing_required(self):
  xml='<manifest xmlns:d="http://schemas.android.com/apk/distribution" package="de.own.game" split="assetPackInstallTime"><d:module d:type="asset-pack"><d:fusing d:include="true"/><d:delivery><d:install-time/></d:delivery></d:module></manifest>'
  g.install_time(xml,'de.own.game')
  for changed in [xml.replace('install-time','on-demand'),xml.replace('include="true"','include="false"'),xml.replace('de.own.game','de.other.game'),xml.replace('assetPackInstallTime','differentPack')]:
   with self.subTest(changed=changed),self.assertRaises(ValueError):g.install_time(changed,'de.own.game')
 def test_full_module_payload_includes_pack(self):self.assertEqual(set(g.payload(bundle(BASE))),set(BASE))
 def test_missing_install_time_pack_rejected(self):
  with self.assertRaises(ValueError):g.payload(bundle({k:v for k,v in BASE.items() if not k.startswith('assetPackInstallTime/')}))
 def test_changed_or_missing_pack_asset_rejected(self):
  for files in [{**BASE,'assetPackInstallTime/assets/data.pck':b'stale'},{k:v for k,v in BASE.items() if not k.endswith('OFL.txt')}]:
   with self.subTest(files=files),self.assertRaises(ValueError):g.equal_payload(bundle(BASE),bundle(files))
 def test_unsafe_archive_names_rejected(self):
  for name in ['../leak','/absolute','base/../x','base//x','base\\x']:
   with self.subTest(name=name),self.assertRaises(ValueError):g.payload(bundle({**BASE,name:b'x'}))
 def test_duplicate_names_rejected(self):
  b=io.BytesIO()
  with zipfile.ZipFile(b,'w') as z:
   for k,v in BASE.items():z.writestr(k,v)
   z.writestr('base/dex/classes.dex',b'other')
  with self.assertRaises(ValueError):g.payload(b.getvalue())
 def test_only_signature_metadata_may_change(self):
  g.equal_payload(bundle(BASE),bundle({**BASE,'META-INF/X.SF':b'sig','META-INF/X.RSA':b'block','META-INF/MANIFEST.MF':b'mf'}))
  with self.assertRaises(ValueError):g.equal_payload(bundle(BASE),bundle({**BASE,'META-INF/real-license.txt':b'missing-before'}))
 def test_source_context_wrong_event_path_sha_repo_and_branch_rejected(self):
  g.require_manual(CTX)
  for delta in [{'GITHUB_EVENT_NAME':'push'},{'GITHUB_WORKFLOW_REF':'owner/repo/.github/workflows/other.yml@refs/heads/main'},{'GITHUB_SHA':'bad'},{'GITHUB_REF':'refs/heads/other'},{'GITHUB_REPOSITORY':'other/repo'},{'GITHUB_RUN_ATTEMPT':'2'}]:
   with self.subTest(delta=delta),self.assertRaises(ValueError):g.require_manual({**CTX,**delta})
 def test_actual_prepare_and_exact_transfer_accept(self):
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t);(p/'raw.aab').write_bytes(bundle({**BASE,'META-INF/BUILD.SF':b'sig','META-INF/BUILD.RSA':b'block'}));g.prepare(p/'raw.aab',p/'source',CTX)
   files={f.name:f.read_bytes() for f in (p/'source').iterdir()};archive=bundle(files);digest=hashlib.sha256(archive).hexdigest();meta={'id':11,'name':'source-10','digest':'sha256:'+digest,'expired':False,'workflow_run':{'id':10,'repository_id':9,'head_repository_id':9,'head_branch':'main','head_sha':'a'*40}}
   g.unpack(archive,meta,digest,11,'source-10',CTX,p/'input');g.recheck(p/'input',CTX)
   for field,delta in [('id',12),('digest','sha256:'+'0'*64),('name','other'),('expired',True)]:
    with self.subTest(field=field),self.assertRaises(ValueError):g.unpack(archive,{**meta,field:delta},digest,11,'source-10',CTX,p/('bad-'+field))
   for field,value in [('id',99),('head_sha','b'*40),('head_branch','other'),('repository_id',8),('head_repository_id',8)]:
    with self.subTest(runField=field),self.assertRaises(ValueError):g.unpack(archive,{**meta,'workflow_run':{**meta['workflow_run'],field:value}},digest,11,'source-10',CTX,p/('bad-run-'+field))
   (p/'input/app.aab').write_bytes(bundle({**BASE,'assetPackInstallTime/assets/data.pck':b'old'}))
   with self.assertRaises(ValueError):g.recheck(p/'input',CTX)
 def test_complete_signature_manifest_covers_asset_pack(self):
  files={**BASE,'assetPackInstallTime/assets/'+('long-name-'*10)+'.txt':b'long named original'}
  def folded(line):return '\r\n '.join(line[i:i+70] for i in range(0,len(line),70))
  manifest=('Manifest-Version: 1.0\r\n\r\n'+''.join(folded('Name: '+n)+'\r\nSHA-256-Digest: '+base64.b64encode(hashlib.sha256(v).digest()).decode()+'\r\n\r\n' for n,v in files.items())).encode()
  sf=('Signature-Version: 1.0\r\nSHA-256-Digest-Manifest: '+base64.b64encode(hashlib.sha256(manifest).digest()).decode()+'\r\n\r\n').encode()
  signed={**files,'META-INF/MANIFEST.MF':manifest,'META-INF/X.SF':sf,'META-INF/X.RSA':b'structure-only; actual workflow separately verifies crypto with jarsigner'}
  g.signature_coverage(bundle(signed))
  for delta in [{'assetPackInstallTime/assets/data.pck':b'tampered'},{'META-INF/X.SF':b'Signature-Version: 1.0\n\n'}]:
   with self.subTest(delta=delta),self.assertRaises(ValueError):g.signature_coverage(bundle({**signed,**delta}))
 def test_incomplete_signature_coverage_rejected(self):
  with self.assertRaises(ValueError):g.signature_coverage(bundle({**BASE,'META-INF/MANIFEST.MF':b'Manifest-Version: 1.0\n\n','META-INF/X.SF':b'bad','META-INF/X.RSA':b'block'}))
if __name__=='__main__':unittest.main()
