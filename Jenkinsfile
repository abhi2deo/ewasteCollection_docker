pipeline {
  agent any

  parameters {
    booleanParam(name: 'FAULTY_RELEASE', defaultValue: false,
                 description: 'Tick to build and deploy a deliberately broken version (rollback demo)')
  }

  environment {
    REPO   = "YOURUSERNAME/ewaste-portal"
    DEPLOY = "ewaste-portal"
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Prepare') {
      steps {
        script {
          env.TAG   = params.FAULTY_RELEASE ? "${env.BUILD_NUMBER}-faulty" : "${env.BUILD_NUMBER}"
          env.IMAGE = "${env.REPO}:${env.TAG}"
          env.ROLLED_BACK = 'false'
          echo "Release image: ${env.IMAGE} (faulty=${params.FAULTY_RELEASE})"
        }
      }
    }

    stage('Build Image') {
      steps {
        sh 'docker build --build-arg FAULTY=${FAULTY_RELEASE} -t $IMAGE .'
      }
    }

    stage('Push Image') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                          usernameVariable: 'DH_USER',
                                          passwordVariable: 'DH_PASS')]) {
          sh 'echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin'
          sh 'docker push $IMAGE'
          script {
            // Only healthy builds are allowed to move "latest"
            if (!params.FAULTY_RELEASE) {
              sh 'docker tag $IMAGE $REPO:latest'
              sh 'docker push $REPO:latest'
            }
          }
        }
      }
    }

    stage('Deploy & Detect Failure') {
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
          script {
            env.PREV_IMAGE = sh(returnStdout: true, script:
              "kubectl get deployment $DEPLOY -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true").trim()
            echo "Current stable image before deploy: ${env.PREV_IMAGE ?: 'none'}"

            sh 'sed "s|IMAGE_PLACEHOLDER|$IMAGE|" k8s/deployment.yaml | kubectl apply -f -'
            sh 'kubectl annotate deployment $DEPLOY kubernetes.io/change-cause="Jenkins build $BUILD_NUMBER: $IMAGE" --overwrite'

            int rc = sh(returnStatus: true, script: 'kubectl rollout status deployment/$DEPLOY --timeout=90s')

            if (rc != 0) {
              echo "ROLLOUT FAILED for ${env.IMAGE}. Collecting evidence, then rolling back."
              sh 'kubectl get pods -l app=$DEPLOY || true'
              sh 'kubectl describe pods -l app=$DEPLOY | tail -n 25 || true'
              sh 'kubectl logs -l app=$DEPLOY --tail=20 || true'

              if (!env.PREV_IMAGE) {
                error('Rollout failed and there is no previous release to roll back to.')
              }
              sh 'kubectl rollout undo deployment/$DEPLOY'
              sh 'kubectl rollout status deployment/$DEPLOY --timeout=120s'
              env.ROLLED_BACK = 'true'
              echo "Rolled back to previous stable release: ${env.PREV_IMAGE}"
            } else {
              echo "Rollout succeeded for ${env.IMAGE}"
            }
          }
        }
      }
    }

    stage('Verify Application') {
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
          sh 'kubectl get deployment $DEPLOY'
          sh 'kubectl get pods -l app=$DEPLOY'
          sh 'echo "Running image: $(kubectl get deployment $DEPLOY -o jsonpath=\'{.spec.template.spec.containers[0].image}\')"'
          sh 'kubectl rollout history deployment/$DEPLOY'

          // Smoke test from inside the cluster
          sh 'kubectl run smoke-$BUILD_NUMBER --rm -i --restart=Never --image=curlimages/curl:8.8.0 --command -- curl -sf http://ewaste-portal-svc/ | grep -o "<title>[^<]*</title>"'
          echo 'Smoke test passed: application is serving traffic.'

          script {
            if (env.ROLLED_BACK == 'true') {
              // Use error('...') instead if you want the build itself to show red
              currentBuild.result = 'UNSTABLE'
              echo 'Build marked UNSTABLE: the new release failed and was automatically rolled back.'
            }
          }
        }
      }
    }
  }

  post {
    always { sh 'docker logout || true' }
  }
}