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

    stage('SAST & Manifest Lint') {
      steps {
        powershell '''
          $ErrorActionPreference = "Continue"
          Write-Host "Running Trivy filesystem scan (HIGH,CRITICAL) on repo..."
          docker run --rm -v "$env:WORKSPACE:/repo" -w /repo aquasec/trivy:0.50.0 fs --no-progress --severity HIGH,CRITICAL --exit-code 1 .
          if ($LASTEXITCODE -ne 0) { Write-Error "Trivy filesystem scan found HIGH/CRITICAL issues"; exit 1 }

          if (Test-Path "manifests") {
            Write-Host "Linting Kubernetes manifests with kubeval (Docker Hub mirror)..."
            docker run --rm -v "$env:WORKSPACE/manifests:/manifests" cytopia/kubeval:latest -d /manifests
            Write-Host "Running kube-linter for richer checks..."
            docker run --rm -v "$env:WORKSPACE/manifests:/manifests" stackrox/kube-linter:v0.6.8 lint /manifests
          }
        '''
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

            # Compute image tag consistently (7-char commit or build number)
            if ($env:GIT_COMMIT -and $env:GIT_COMMIT.Length -ge 7) { $TAG = $env:GIT_COMMIT.Substring(0,7) } else { $TAG = $env:BUILD_NUMBER }
            $localTag = "$($env:ECR_REPO):$TAG"
            $remoteTag = "$($REPO_URL):$TAG"

            docker build -t "$localTag" .
            docker tag "$localTag" "$remoteTag"

            # Push image first, then scan the remote tag in ECR with Trivy (auth via ECR password)
            Write-Host "Pushing image to ECR..."
            docker push "$remoteTag"

            Write-Host "Scanning pushed image in ECR with Trivy (HIGH,CRITICAL)..."
            $ecrPwd = $(aws ecr get-login-password --region $env:AWS_REGION)
            if (-not $ecrPwd) { throw "Failed to obtain ECR password for Trivy auth" }
            docker run --rm aquasec/trivy:0.50.0 image --no-progress --severity HIGH,CRITICAL --exit-code 1 --username AWS --password "$ecrPwd" "$remoteTag"
            if ($LASTEXITCODE -ne 0) { throw "Trivy remote image scan failed with exit code $LASTEXITCODE" }
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
            # Create/update a simple application secret (placeholder for Vault/ASM)
            kubectl create secret generic app-secrets --from-literal=APP_BANNER="GlobalLogic" --dry-run=client -o yaml | kubectl apply -f -
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
            if ($env:GIT_COMMIT -and $env:GIT_COMMIT.Length -ge 7) { $TAG = $env:GIT_COMMIT.Substring(0,7) } else { $TAG = $env:BUILD_NUMBER }
            $remoteTag = "$($REPO_URL):$TAG"
            kubectl set image deployment/nginx-deployment nginx=$remoteTag
            # Wait up to 5 minutes for rollout
            if (-not (kubectl rollout status deployment/nginx-deployment --timeout=5m)) {
              Write-Host "Rollout status timed out - collecting diagnostics"
              kubectl get deployment nginx-deployment -o wide
              kubectl describe deployment nginx-deployment
              kubectl get rs -o wide
              kubectl get pods -o wide
              kubectl describe pods
              kubectl get events --sort-by=.lastTimestamp | Select-Object -Last 100
              throw "Deployment rollout timed out"
            }
          '''
        }
      }
    }

    stage('DAST - ZAP Baseline') {
      steps {
        powershell '''
          $ErrorActionPreference = "Continue"
          aws eks update-kubeconfig --name $env:CLUSTER_NAME --region $env:AWS_REGION
          $host = (kubectl get svc nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
          if (-not $host) { Write-Host "Service hostname not ready, skipping ZAP"; exit 0 }
          $url = "http://$host"
          Write-Host "Running ZAP Baseline scan against $url"
          docker run --rm -v "$env:WORKSPACE:/zap/wrk" -t owasp/zap2docker-stable zap-baseline.py -t $url -r zap.html
          if ($LASTEXITCODE -ne 0) { Write-Host "ZAP baseline returned non-zero ($LASTEXITCODE). Proceeding (non-blocking)."; $global:LASTEXITCODE = 0 }
        '''
      }
      post {
        always {
          archiveArtifacts artifacts: 'zap.html', allowEmptyArchive: true
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
