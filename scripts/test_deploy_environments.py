"""Exercise deploy/rollback scripts against a fake kubectl, never a cluster."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
IMAGE="ghcr.io/slmanuel/devops-java-service@sha256:"+"a"*64
FAKE = r'''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
args=sys.argv[1:];work=Path(os.environ['MOCK_DIR']);target=os.environ['TARGET_ENVIRONMENT']
with (work/'calls').open('a') as f:f.write(json.dumps(args)+'\n')
if args[:2]==['config','current-context']:
 print(os.environ.get('MOCK_CONTEXT',target));sys.exit()
if args[:2]==['set','image']:
 image=next(a[4:] for a in args if a.startswith('app='))
 print(json.dumps({'apiVersion':'apps/v1','kind':'Deployment','metadata':{'name':'devops-java-service','namespace':'development'},'spec':{'template':{'spec':{'containers':[{'name':'app','image':image}]}}}}));sys.exit()
if args[:2]!=['-n',target]:sys.exit('Unexpected namespace or invocation')
args=args[2:]
if args[:2]==['get','deployment']:
 if any('jsonpath=' in a for a in args):print('2');sys.exit()
 print(json.dumps({'apiVersion':'apps/v1','kind':'Deployment','metadata':{'name':'devops-java-service','namespace':target},'spec':{'template':{'spec':{'containers':[{'name':'app','image':'previous-image'}]}}}}));sys.exit()
if args[:2]==['get','secret']:
 print(json.dumps({'apiVersion':'v1','kind':'Secret','metadata':{'name':'pipeline-env','namespace':target},'data':{'DEMO_MESSAGE':'cHJldmlvdXM='},'type':'Opaque'}));sys.exit()
if args[:2]==['create','secret']:
 print(json.dumps({'apiVersion':'v1','kind':'Secret','metadata':{'name':'pipeline-env','namespace':target},'data':{'DEMO_MESSAGE':'Y2FuZGlkYXRl'},'type':'Opaque'}));sys.exit()
if args[0]=='apply':
 file=args[args.index('-f')+1]
 text=sys.stdin.read() if file=='-' else Path(file).read_text()
 obj=json.loads(text)
 if obj['metadata']['namespace']!=target:sys.exit('Wrong applied namespace')
 (work/(obj['kind']+'.json')).write_text(text);print('applied');sys.exit()
if args[:2]==['rollout','status']:
 if (work/'fail-rollout').exists():
  (work/'fail-rollout').unlink();sys.exit(1)
 print('ready');sys.exit()
sys.exit('Unexpected kubectl invocation')
'''

class DeployTests(unittest.TestCase):
 def run_script(self,name,env):
  return subprocess.run(['sh',str(ROOT/'scripts'/name)],cwd=ROOT,env=env,text=True,capture_output=True)
 def setup_fixture(self,temp,target):
  directory=Path(temp);binary=directory/'kubectl';binary.write_text(FAKE);binary.chmod(0o700)
  (directory/'DEMO_MESSAGE').write_text('non-sensitive-test-value')
  return dict(os.environ,PATH=str(directory)+os.pathsep+os.environ['PATH'],PIPELINE_DIR=str(directory),MOCK_DIR=str(directory),TARGET_ENVIRONMENT=target,KUBECONFIG=str(directory/'fake-kubeconfig'),IMAGE=IMAGE,LOCAL_DEMO_LEGACY='false')
 def test_same_digest_three_targets_and_success_clears_marker(self):
  for target in ('development','qa','production'):
   with self.subTest(target=target),tempfile.TemporaryDirectory() as temp:
    env=self.setup_fixture(temp,target);result=self.run_script('deploy.sh',env)
    self.assertEqual(result.returncode,0,result.stderr)
    deployed=json.loads((Path(temp)/'Deployment.json').read_text())
    self.assertEqual(deployed['metadata']['namespace'],target)
    self.assertEqual(deployed['spec']['template']['spec']['containers'][0]['image'],IMAGE)
    self.assertFalse((Path(temp)/target/'deploy-started').exists())
 def test_wrong_context_and_mutable_tag_fail_before_mutation(self):
  for extra in ({'MOCK_CONTEXT':'wrong-cluster'},{'IMAGE':'ghcr.io/slmanuel/devops-java-service:latest'}):
   with tempfile.TemporaryDirectory() as temp:
    env=self.setup_fixture(temp,'production');env.update(extra)
    self.assertNotEqual(self.run_script('deploy.sh',env).returncode,0)
    self.assertFalse((Path(temp)/'Deployment.json').exists())
    self.assertFalse((Path(temp)/'Secret.json').exists())
 def test_failed_qa_restores_only_qa_and_previous_secret(self):
  with tempfile.TemporaryDirectory() as temp:
   directory=Path(temp);env=self.setup_fixture(temp,'qa');(directory/'fail-rollout').touch()
   self.assertNotEqual(self.run_script('deploy.sh',env).returncode,0)
   self.assertTrue((directory/'qa/deploy-started').exists())
   result=self.run_script('rollback.sh',env);self.assertEqual(result.returncode,0,result.stderr)
   self.assertEqual(json.loads((directory/'Secret.json').read_text())['data']['DEMO_MESSAGE'],'cHJldmlvdXM=')
   self.assertEqual(json.loads((directory/'Deployment.json').read_text())['spec']['template']['spec']['containers'][0]['image'],'previous-image')
   self.assertFalse((directory/'qa/deploy-started').exists())
   self.assertFalse((directory/'production').exists())
 def test_no_marker_does_not_roll_back_healthy_environment(self):
  with tempfile.TemporaryDirectory() as temp:
   env=self.setup_fixture(temp,'development')
   self.assertEqual(self.run_script('rollback.sh',env).returncode,0)
   self.assertFalse((Path(temp)/'calls').exists())

if __name__=='__main__':unittest.main()
