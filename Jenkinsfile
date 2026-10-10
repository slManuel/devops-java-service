pipeline {
  agent {
    kubernetes {
      cloud 'kubernetes'
      defaultContainer 'jnlp'
      yaml """
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins-pipeline
  automountServiceAccountToken: false
  nodeSelector:
    workload: jenkins
  imagePullSecrets:
    - name: ghcr-pull
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
  containers:
    - name: jnlp
      image: ${params.AGENT_IMAGE}
      resources:
        requests: {cpu: 200m, memory: 256Mi}
        limits: {cpu: '1', memory: 768Mi}
      volumeMounts:
        - {name: pipeline, mountPath: /run/pipeline}
        - {name: vault-token, mountPath: /var/run/vault, readOnly: true}
        - {name: vault-ca, mountPath: /etc/vault-ca, readOnly: true}
    - name: buildkit
      image: moby/buildkit:rootless@sha256:65eca3c01cd1180c8f64565c4e3c5983af5145818b0e6fa863385d099eb73855
      command: [sh, -c, 'sleep infinity']
      env:
        - {name: BUILDKITD_FLAGS, value: '--oci-worker-no-process-sandbox'}
        - {name: DOCKER_CONFIG, value: /run/pipeline/docker}
      securityContext:
        seccompProfile: {type: Unconfined}
        appArmorProfile: {type: Unconfined}
      resources:
        requests: {cpu: 250m, memory: 512Mi}
        limits: {cpu: '1', memory: 1Gi}
      volumeMounts:
        - {name: pipeline, mountPath: /run/pipeline}
  volumes:
    - name: pipeline
      emptyDir: {medium: Memory, sizeLimit: 256Mi}
    - name: vault-token
      projected:
        defaultMode: 0440
        sources:
          - serviceAccountToken: {audience: vault, expirationSeconds: 600, path: token}
    - name: vault-ca
      configMap: {name: vault-ca}
"""
    }
  }
  parameters {
    string(name: 'SOURCE_BUILD_NUMBER', defaultValue: '', description: 'QA: successful develop build; production: successful qa build. Must contain the exact same Git tree.')
    string(name: 'AGENT_IMAGE', defaultValue: 'ghcr.io/slmanuel/jenkins-agent:REPLACE_COMMIT', description: 'Image built from the deployment repo, pinned by commit or digest')
  }
  options {
    disableConcurrentBuilds()
    timeout(time: 30, unit: 'MINUTES')
    skipDefaultCheckout(true)
  }
  environment {
    REGISTRY_IMAGE = 'ghcr.io/slmanuel/devops-java-service'
  }
  stages {
    stage('Checkout') {
      steps {
        script {
          if (params.AGENT_IMAGE.contains('REPLACE_')) { error('Configure the published agent image first') }
          def source = checkout scm
          env.GIT_COMMIT = source.GIT_COMMIT
          if (env.CHANGE_ID) { error('PR validation runs in GitHub Actions; this job never deploys PRs') }
          def targetEnvironment = ['develop':'development', 'qa':'qa', 'main':'production'][env.BRANCH_NAME]
          if (!targetEnvironment) { error('Only develop, qa and main may deploy') }
          env.TARGET_ENVIRONMENT = targetEnvironment
          if (env.BRANCH_NAME != 'develop' && !(params.SOURCE_BUILD_NUMBER ==~ /[1-9][0-9]*/)) {
            error('Select a successful source build: develop for QA, qa for production')
          }
          env.IMAGE = "${env.REGISTRY_IMAGE}:${env.GIT_COMMIT}"
        }
      }
    }
    stage('Vault before build') {
      when { branch 'develop' }
      steps {
        withEnv(['TARGET_ENVIRONMENT=development']) { sh 'sh scripts/read-vault.sh' }
      }
    }
    stage('Build and test Java 21') {
      when { branch 'develop' }
      steps {
        sh '''set +x
export DEMO_MESSAGE="$(cat /run/pipeline/DEMO_MESSAGE)"
sh scripts/test.sh
'''

      }
    }
    stage('Build and push immutable image') {
      when { branch 'develop' }
      steps {
        withCredentials([usernamePassword(credentialsId: 'registry-credentials', usernameVariable: 'REGISTRY_USER', passwordVariable: 'REGISTRY_PASSWORD')]) {
          sh '''set +x
umask 077
mkdir -p /run/pipeline/docker
auth=$(printf '%s:%s' "$REGISTRY_USER" "$REGISTRY_PASSWORD" | base64 | tr -d '\n')
jq -cn --arg auth "$auth" '{auths:{"ghcr.io":{auth:$auth}}}' > /run/pipeline/docker/config.json
'''
          container('buildkit') {
            sh 'set +x; export DEMO_MESSAGE="$(cat /run/pipeline/DEMO_MESSAGE)"; buildctl-daemonless.sh build --frontend dockerfile.v0 --local context=. --local dockerfile=. --output type=image,name=$IMAGE,push=true --metadata-file /run/pipeline/image-metadata.json'
          }
        }
        script {
          env.IMAGE = sh(script: "jq -er '.\"containerimage.digest\"' /run/pipeline/image-metadata.json", returnStdout: true).trim()
          env.IMAGE = "${env.REGISTRY_IMAGE}@${env.IMAGE}"
        }
      }
    }
    stage('Recover validated digest') {
      when { not { branch 'develop' } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'promotion-reader', usernameVariable: 'PROMOTION_USER', passwordVariable: 'PROMOTION_TOKEN')]) {
          sh 'sh scripts/fetch-release.sh'
        }
        script {
          env.IMAGE = sh(script: "jq -er '.image' release.json", returnStdout: true).trim()
        }
      }
    }
    stage('Deploy selected environment') {
      steps {
        withCredentials([file(credentialsId: "kubeconfig-${env.TARGET_ENVIRONMENT}", variable: 'KUBECONFIG')]) {
          script { env.DEPLOY_ENVIRONMENT = env.TARGET_ENVIRONMENT }
          sh 'if [ "$TARGET_ENVIRONMENT" != development ]; then sh scripts/read-vault.sh; fi'
          sh 'sh scripts/deploy.sh'
        }
      }
    }
    stage('Record validated release') {
      steps {
        sh 'sh scripts/record-release.sh'
        archiveArtifacts artifacts: 'release.json', fingerprint: true
      }
    }
  }

  post {
    failure {
      script {
        if (env.DEPLOY_ENVIRONMENT && fileExists("/run/pipeline/${env.DEPLOY_ENVIRONMENT}/deploy-started")) {
          withEnv(["TARGET_ENVIRONMENT=${env.DEPLOY_ENVIRONMENT}"]) {
            withCredentials([file(credentialsId: "kubeconfig-${env.DEPLOY_ENVIRONMENT}", variable: 'KUBECONFIG')]) {
              sh 'sh scripts/rollback.sh'
            }
          }
        }
      }
    }
    cleanup {
      sh 'set +x; find /run/pipeline -type f -exec truncate -s 0 {} +'
      deleteDir()
    }
  }
}
