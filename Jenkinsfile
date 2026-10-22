pipeline {
  agent any

  parameters {
    choice(name: 'DEPLOY_TARGET', choices: ['test', 'production'], description: 'Choose deployment target')
    booleanParam(name: 'DEPLOY_TO_K8S', defaultValue: true, description: 'Deploy to Docker Desktop Kubernetes')
  }

  environment {
    IMAGE_NAME = 'abhinavdeo/ewaste-collection'
    K8S_NAMESPACE = 'default'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh 'git log -1 --oneline'
      }
    }

    stage('Parallel validation') {
      parallel {
        stage('HTML checks') {
          steps {
            sh '''
              test -s index.html
              grep -q "Collection centres" index.html
              grep -q "Recycling instructions" index.html
              grep -q "Successfully recycled" index.html
              echo "HTML content checks passed"
            '''
          }
        }
        stage('Manifest checks') {
          steps {
            sh '''
              test -s Dockerfile
              test -s deployment.yaml
              grep -q "kind: Deployment" deployment.yaml
              grep -q "readinessProbe" deployment.yaml
              echo "Deployment manifest checks passed"
            '''
          }
        }
      }
    }

    stage('Build image') {
      steps {
        script {
          env.IMAGE_TAG = "${env.BUILD_NUMBER}"
        }
        sh 'docker build -t $IMAGE_NAME:$IMAGE_TAG -t $IMAGE_NAME:latest .'
      }
    }

    stage('Push image') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
          sh '''
            echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
            docker push "$IMAGE_NAME:$IMAGE_TAG"
            docker push "$IMAGE_NAME:latest"
            docker logout
          '''
        }
      }
    }

    stage('Deploy to Kubernetes') {
      when {
        expression { return params.DEPLOY_TO_K8S }
      }
      steps {
        withCredentials([file(credentialsId: 'kubeconfig-docker-desktop', variable: 'KUBECONFIG_FILE')]) {
          sh '''
            export KUBECONFIG="$KUBECONFIG_FILE"
            sed "s|DOCKERHUB_USERNAME|${IMAGE_NAME%%/*}|" deployment.yaml | kubectl apply -n "$K8S_NAMESPACE" -f -
            kubectl set image deployment/ewaste-portal ewaste-portal="$IMAGE_NAME:$IMAGE_TAG" -n "$K8S_NAMESPACE"
            if ! kubectl rollout status deployment/ewaste-portal -n "$K8S_NAMESPACE" --timeout=120s; then
              echo "Rollout failed; automatically rolling back to previous stable revision."
              kubectl rollout undo deployment/ewaste-portal -n "$K8S_NAMESPACE"
              kubectl rollout status deployment/ewaste-portal -n "$K8S_NAMESPACE" --timeout=120s
              exit 1
            fi
          '''
        }
      }
    }

    stage('Archive manifest') {
      steps {
        archiveArtifacts artifacts: 'index.html,Dockerfile,deployment.yaml,Jenkinsfile', fingerprint: true
      }
    }
  }

  post {
    always {
      echo "Pipeline ${currentBuild.currentResult}: build ${env.BUILD_NUMBER}"
    }
  }
}
