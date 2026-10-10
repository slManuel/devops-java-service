#!/usr/bin/env python3
"""Check shared security/deploy contracts; cloud promotion extends the historical demo."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
aws=(root/'Jenkinsfile').read_text()
local=(root/'local-demo/Jenkinsfile').read_text()
assert re.findall(r"stage\('([^']+)'\)",aws)==[
    'Checkout','Vault before build','Build and test Java 21','Build and push immutable image',
    'Recover validated digest','Deploy selected environment','Record validated release']
assert aws.count('buildctl-daemonless.sh build')==1 and 'push=false' not in aws
assert aws.count("when { branch 'develop' }")==3
assert "['develop':'development', 'qa':'qa', 'main':'production']" in aws
assert 'SOURCE_BUILD_NUMBER' in aws and 'sh scripts/fetch-release.sh' in aws
assert 'kubeconfig-${env.TARGET_ENVIRONMENT}' in aws
assert '/run/pipeline/${env.DEPLOY_ENVIRONMENT}/deploy-started' in aws
assert 'archiveArtifacts artifacts:' in aws
for text in (aws,local):
    assert 'def source = checkout scm\n          env.GIT_COMMIT = source.GIT_COMMIT' in text
    assert "sh 'sh scripts/read-vault.sh'" in text
    assert "sh 'sh scripts/deploy.sh'" in text and "sh 'sh scripts/rollback.sh'" in text
    assert 'serviceAccountToken: {audience: vault, expirationSeconds: 600, path: token}' in text
    assert 'emptyDir: {medium: Memory, sizeLimit: 256Mi}' in text
    assert 'env.IMAGE = "${env.REGISTRY_IMAGE}@${env.IMAGE}"' in text
    assert 'seccompProfile: {type: Unconfined}\n        appArmorProfile: {type: Unconfined}' in text
assert 'registry.insecure' not in aws and 'FAIL_ROLLOUT' not in aws and 'LOCAL_DEMO_LEGACY' not in aws
assert not re.search(r'172\.20\.|cuscatlan-|local-demo/',aws)
print('PASS: one develop build/push, branch-selected promotions, exact artifact/tree, scoped rollback and shared JWT/TLS security; historical demo remains separate.')
