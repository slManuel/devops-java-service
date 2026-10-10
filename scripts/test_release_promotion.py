"""Test release transfer using fake Jenkins HTTP responses and Git metadata."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
IMAGE='ghcr.io/slmanuel/devops-java-service@sha256:'+'a'*64
TREE='b'*40
GIT = "#!/usr/bin/env sh\ncase \"$2\" in HEAD) printf '%s' \"$MOCK_COMMIT\";; *) printf '%s' \"$MOCK_TREE\";; esac\n"
CURL = r'''#!/usr/bin/env python3
import os,sys
from pathlib import Path
url=sys.argv[-1]
root=Path(os.environ['MOCK_DIR'])
if url.endswith('api/json?tree=result,building'):print((root/'status.json').read_text())
elif url.endswith('/artifact/release.json'):print((root/'source-release.json').read_text())
else:sys.exit('Unexpected source URL')
'''
class PromotionTests(unittest.TestCase):
 def setup_fixture(self,temp,branch):
  d=Path(temp)
  for name,body in [('git',GIT),('curl',CURL)]:
   p=d/name;p.write_text(body);p.chmod(0o700)
  target={'develop':'development','qa':'qa','main':'production'}[branch]
  source='develop' if branch=='qa' else 'qa'
  manifest={'schema':1,'image':IMAGE,'source_commit':'c'*40,'source_tree':TREE,'validated_environment':'development' if source=='develop' else 'qa','validated_job':'service/'+source,'validated_build_number':'7'}
  (d/'source-release.json').write_text(json.dumps(manifest))
  (d/'status.json').write_text(json.dumps({'result':'SUCCESS','building':False}))
  return dict(os.environ,PATH=str(d)+os.pathsep+os.environ['PATH'],MOCK_DIR=str(d),MOCK_TREE=TREE,MOCK_COMMIT='d'*40,BRANCH_NAME=branch,TARGET_ENVIRONMENT=target,BUILD_NUMBER='12',JOB_NAME='service/'+branch,BUILD_URL='http://jenkins/job/service/job/'+branch+'/12/',SOURCE_BUILD_NUMBER='7',PROMOTION_USER='fixture-reader',PROMOTION_TOKEN='fixture-token',IMAGE=IMAGE)
 def execute(self,script,env,temp):
  return subprocess.run(['sh',str(ROOT/'scripts'/script)],cwd=temp,env=env,text=True,capture_output=True)
 def test_promotes_identical_digest_with_different_merge_commit(self):
  for branch in ['qa','main']:
   with self.subTest(branch=branch),tempfile.TemporaryDirectory() as temp:
    env=self.setup_fixture(temp,branch)
    result=self.execute('fetch-release.sh',env,temp);self.assertEqual(result.returncode,0,result.stderr)
    result=self.execute('record-release.sh',env,temp);self.assertEqual(result.returncode,0,result.stderr)
    release=json.loads((Path(temp)/'release.json').read_text())
    self.assertEqual(release['image'],IMAGE)
    self.assertEqual(release['source_commit'],'c'*40)
    self.assertEqual(release['validated_commit'],'d'*40)
    self.assertEqual(release['validated_environment'],env['TARGET_ENVIRONMENT'])
 def test_rejects_changed_tree_failed_source_mutable_digest_or_wrong_environment(self):
  for kind in ['tree','failed','digest','environment','job','build']:
   with self.subTest(kind=kind),tempfile.TemporaryDirectory() as temp:
    env=self.setup_fixture(temp,'qa');d=Path(temp)
    if kind=='tree':env['MOCK_TREE']='e'*40
    elif kind=='failed':(d/'status.json').write_text(json.dumps({'result':'FAILURE','building':False}))
    else:
     release=json.loads((d/'source-release.json').read_text())
     key,value={'digest':('image','ghcr.io/slmanuel/devops-java-service:latest'),'environment':('validated_environment','production'),'job':('validated_job','other/develop'),'build':('validated_build_number','99')}[kind]
     release[key]=value;(d/'source-release.json').write_text(json.dumps(release))
    self.assertNotEqual(self.execute('fetch-release.sh',env,temp).returncode,0)
 def test_development_records_immutable_origin(self):
  with tempfile.TemporaryDirectory() as temp:
   env=self.setup_fixture(temp,'develop')
   result=self.execute('record-release.sh',env,temp);self.assertEqual(result.returncode,0,result.stderr)
   release=json.loads((Path(temp)/'release.json').read_text())
   self.assertEqual(release['source_tree'],TREE)
   self.assertEqual(release['source_commit'],'d'*40)
   self.assertEqual(release['validated_environment'],'development')
if __name__=='__main__':unittest.main()
