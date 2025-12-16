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

            Write-Host "ECR Registry: $ECR_REG"
            Write-Host "Repo URL:     $REPO_URL"
            # Clear any stale auth (ignore errors)
            try { docker logout $ECR_REG | Out-Null } catch { }
            # Quick connectivity check
            try { Invoke-WebRequest -UseBasicParsing -Uri "https://$ECR_REG/v2/" -Method GET -TimeoutSec 10 | Out-Null } catch { Write-Host "Connectivity check (expected 401/200) -> $($_.Exception.Message)" }

            $loginOk = $false
            for ($i=0; $i -lt 2 -and -not $loginOk; $i++) {
              try {
                $pwd = $(aws ecr get-login-password --region $env:AWS_REGION)
                if (-not $pwd) { throw "Empty ECR password" }
                if ($i -eq 0) {
                  docker login --username AWS --password $pwd $ECR_REG
                } else {
                  docker login --username AWS --password $pwd "https://$ECR_REG"
                }
                if ($LASTEXITCODE -eq 0) { $loginOk = $true }
              } catch {
                Start-Sleep -Seconds 3
              }
            }
            if (-not $loginOk) { throw "ECR login failed after retries" }

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
