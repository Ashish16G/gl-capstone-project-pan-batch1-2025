pipeline {
  agent any

  parameters {
    string(name: 'AWS_REGION', defaultValue: 'ap-south-1', description: 'AWS region')
    string(name: 'ECR_REPO', defaultValue: 'gl-capactone-project-pan-repo', description: 'ECR repository name')
    string(name: 'CLUSTER_NAME', defaultValue: 'capstone-eks', description: 'EKS cluster name')
  }

  options {
    timestamps()
    ansiColor('xterm')
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Tools Versions') {
      steps {
        sh 'aws --version || true'
        sh 'terraform version || true'
        sh 'kubectl version --client || true'
        sh 'docker --version || true'
      }
    }

    stage('Terraform Init/Plan/Apply') {
      steps {
        dir('infra') {
          sh 'terraform init -input=false'
          sh 'terraform plan -input=false -out=tfplan'
          sh 'terraform apply -input=false -auto-approve tfplan'
        }
      }
    }

    stage('Docker Build and Push to ECR') {
      environment {
        IMAGE_TAG = "${env.GIT_COMMIT?.take(7) ?: env.BUILD_NUMBER}"
      }
      steps {
        script {
          sh '''
            set -e
            ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
            REPO_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"

            aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

            docker build -t ${ECR_REPO}:${IMAGE_TAG} .
            docker tag ${ECR_REPO}:${IMAGE_TAG} ${REPO_URL}:${IMAGE_TAG}
            docker push ${REPO_URL}:${IMAGE_TAG}
          '''
        }
      }
    }

    stage('Deploy to EKS') {
      when { expression { return fileExists('manifests') } }
      steps {
        sh '''
          set -e
          aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}
          kubectl apply -f manifests/
        '''
      }
    }

    stage('Rollout ECR Image') {
      when {
        allOf {
          expression { return params.ECR_REPO?.trim() }
          expression { return fileExists('manifests') }
        }
      }
      steps {
        sh '''
          set -e
          ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
          REPO_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"
          kubectl set image deployment/nginx-deployment nginx=${REPO_URL}:${IMAGE_TAG} --record
          kubectl rollout status deployment/nginx-deployment --timeout=2m
        '''
      }
    }
  }

  post {
    always {
      echo 'Pipeline finished.'
    }
  }
}
