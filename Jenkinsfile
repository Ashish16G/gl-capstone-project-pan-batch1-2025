pipeline {
  agent any

  parameters {
    string(name: 'AWS_REGION', defaultValue: 'ap-south-1', description: 'AWS region')
    string(name: 'ECR_REPO', defaultValue: 'gl-capactone-project-pan-repo', description: 'ECR repository name')
    string(name: 'CLUSTER_NAME', defaultValue: 'capstone-eks', description: 'EKS cluster name')
  }

  options {
    timestamps()
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Tools Versions') {
      steps {
        powershell '''
          $ErrorActionPreference = "Continue"
          aws --version
          terraform version
          kubectl version --client
          docker --version
        '''
      }
    }

    stage('AWS Identity Check') {
      steps {
        withCredentials([
          string(credentialsId: 'AWS_ACCESS_KEY_ID', variable: 'AWS_ACCESS_KEY_ID'),
          string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY')
        ]) {
          powershell '''
            $ErrorActionPreference = "Stop"
            Write-Host "Checking AWS identity..."
            aws sts get-caller-identity
          '''
        }
      }
    }

    stage('Terraform Init/Plan/Apply') {
      steps {
        dir('infra') {
          withCredentials([
            string(credentialsId: 'AWS_ACCESS_KEY_ID', variable: 'AWS_ACCESS_KEY_ID'),
            string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY')
          ]) {
            powershell '''
              $ErrorActionPreference = "Stop"
              terraform init -input=false
              terraform plan -input=false -out=tfplan
              terraform apply -input=false -auto-approve tfplan
            '''
          }
        }
      }
    }

    stage('Docker Build and Push to ECR') {
      environment {
        IMAGE_TAG = "${env.GIT_COMMIT?.take(7) ?: env.BUILD_NUMBER}"
      }
      steps {
        withCredentials([
          string(credentialsId: 'AWS_ACCESS_KEY_ID', variable: 'AWS_ACCESS_KEY_ID'),
          string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY')
        ]) {
          powershell '''
            $ErrorActionPreference = "Stop"
            $ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text)
            $ECR_REG = "$ACCOUNT_ID.dkr.ecr.$env:AWS_REGION.amazonaws.com"
            $REPO_URL = "$ECR_REG/$env:ECR_REPO"

            aws ecr get-login-password --region $env:AWS_REGION | docker login --username AWS --password-stdin $ECR_REG

            $localTag = "$($env:ECR_REPO):$($env:IMAGE_TAG)"
            $remoteTag = "$($REPO_URL):$($env:IMAGE_TAG)"

            docker build -t "$localTag" .
            docker tag "$localTag" "$remoteTag"
            docker push "$remoteTag"
          '''
        }
      }
    }

    stage('Deploy to EKS') {
      when { expression { return fileExists('manifests') } }
      steps {
        withCredentials([
          string(credentialsId: 'AWS_ACCESS_KEY_ID', variable: 'AWS_ACCESS_KEY_ID'),
          string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY')
        ]) {
          powershell '''
            $ErrorActionPreference = "Stop"
            aws eks update-kubeconfig --name $env:CLUSTER_NAME --region $env:AWS_REGION
            kubectl apply -f manifests/
          '''
        }
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
        withCredentials([
          string(credentialsId: 'AWS_ACCESS_KEY_ID', variable: 'AWS_ACCESS_KEY_ID'),
          string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY')
        ]) {
          powershell '''
            $ErrorActionPreference = "Stop"
            $ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text)
            $REPO_URL = "$ACCOUNT_ID.dkr.ecr.$env:AWS_REGION.amazonaws.com/$env:ECR_REPO"
            $remoteTag = "$($REPO_URL):$($env:IMAGE_TAG)"
            kubectl set image deployment/nginx-deployment nginx=$remoteTag --record
            kubectl rollout status deployment/nginx-deployment --timeout=2m
          '''
        }
      }
    }
  }

  post {
    always {
      echo 'Pipeline finished.'
    }
  }
}
