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

    stage('Ensure Terraform Backend') {
      steps {
        withCredentials([
          string(credentialsId: 'AWS_ACCESS_KEY_ID', variable: 'AWS_ACCESS_KEY_ID'),
          string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY')
        ]) {
          powershell '''
            $ErrorActionPreference = "Stop"
            $bucket = 'gl-capstone-project-pan-2025'
            $table  = 'gl-capstone-project-pan-2025'
            $region = $env:AWS_REGION

            Write-Host "Ensuring S3 bucket $bucket exists in $region..."
            $exists = $false
            try { aws s3api head-bucket --bucket $bucket | Out-Null; $exists = $true } catch { $exists = $false }
            if (-not $exists) {
              if ($region -eq 'us-east-1') {
                aws s3api create-bucket --bucket $bucket | Out-Null
              } else {
                aws s3api create-bucket --bucket $bucket --create-bucket-configuration LocationConstraint=$region | Out-Null
              }
              aws s3api put-bucket-versioning --bucket $bucket --versioning-configuration Status=Enabled | Out-Null
              aws s3api put-public-access-block --bucket $bucket --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true | Out-Null
            }

            Write-Host "Ensuring DynamoDB table $table exists..."
            $tableExists = $false
            try { aws dynamodb describe-table --table-name $table | Out-Null; $tableExists = $true } catch { $tableExists = $false }
            if (-not $tableExists) {
              aws dynamodb create-table --table-name $table --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST | Out-Null
              Write-Host "Waiting for DynamoDB table to be ACTIVE..."
              aws dynamodb wait table-exists --table-name $table
            }
          '''
        }
      }
    }

    stage('SAST & Manifest Lint') {
      steps {
        powershell '''
          $ErrorActionPreference = "Continue"
          Write-Host "Running Trivy filesystem scan (HIGH,CRITICAL) on repo..."
          # Prepare local cache dir for Trivy DB to speed up (Windows path fix to forward slashes for Docker)
          $cachePath = Join-Path $env:WORKSPACE ".trivy-cache"
          if (-not (Test-Path $cachePath)) { New-Item -ItemType Directory -Path $cachePath | Out-Null }
          $cacheMount = ("$cachePath").Replace('\\','/')
          $wsMount = ("$env:WORKSPACE").Replace('\\','/')
          docker run --rm -v "$($wsMount):/repo" -v "$($cacheMount):/root/.cache/trivy" -w /repo aquasec/trivy:0.50.0 fs --no-progress --scanners vuln --severity HIGH,CRITICAL --timeout 15m --exit-code 0 .
          if ($LASTEXITCODE -ne 0) { Write-Host "Trivy filesystem scan returned non-zero; proceeding (informational only)."; $global:LASTEXITCODE = 0 }

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
              terraform init -reconfigure -upgrade -input=false
              # Ensure workspace 'dev'
              try { terraform workspace select dev } catch { terraform workspace new dev }
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

            Write-Host "Scanning pushed image in ECR with Trivy (HIGH,CRITICAL) [informational only]..."
            $ecrPwd = $(aws ecr get-login-password --region $env:AWS_REGION)
            if (-not $ecrPwd) { throw "Failed to obtain ECR password for Trivy auth" }
            # Reuse same cache dir for image scan
            $cachePath = Join-Path $env:WORKSPACE ".trivy-cache"
            if (-not (Test-Path $cachePath)) { New-Item -ItemType Directory -Path $cachePath | Out-Null }
            $cacheMount = ("$cachePath").Replace('\\','/')
            docker run --rm -v "$($cacheMount):/root/.cache/trivy" aquasec/trivy:0.50.0 image --no-progress --scanners vuln --severity HIGH,CRITICAL --timeout 15m --exit-code 0 --username AWS --password "$ecrPwd" "$remoteTag"
            if ($LASTEXITCODE -ne 0) { Write-Host "Trivy remote image scan returned non-zero; proceeding (informational only)."; $global:LASTEXITCODE = 0 }
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
            aws eks wait cluster-active --name $env:CLUSTER_NAME --region $env:AWS_REGION

            # Namespace, config, deployment
            if (Test-Path 'manifests/namespace.yaml') { kubectl apply -f manifests/namespace.yaml }
            if (Test-Path 'manifests/configmap.yaml') { kubectl apply -f manifests/configmap.yaml }
            if (Test-Path 'manifests/secret.yaml') { kubectl apply -f manifests/secret.yaml }
            kubectl apply -f manifests/deployment.yaml

            # Attempt Classic ELB first
            $svcClassic = 'manifests/service-classic.yaml'
            $svcNlb = 'manifests/service-nlb.yaml'
            $created = $false
            if (Test-Path $svcClassic) {
              Write-Host 'Applying Service (Classic ELB attempt)...'
              kubectl apply -f $svcClassic
              # Wait up to ~6 minutes for ELB hostname
              $deadline = (Get-Date).AddMinutes(6)
              do {
                Start-Sleep -Seconds 15
                $host = kubectl get svc nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
                if ($host) { $created = $true; Write-Host "Service ELB hostname: $host" }
              } while (-not $created -and (Get-Date) -lt $deadline)
            }

            if (-not $created -and (Test-Path $svcNlb)) {
              Write-Host 'Classic ELB not ready/unsupported. Falling back to NLB...'
              kubectl apply -f $svcNlb
              $deadline = (Get-Date).AddMinutes(6)
              do {
                Start-Sleep -Seconds 15
                $host = kubectl get svc nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
                if ($host) { Write-Host "Service NLB hostname: $host"; break }
              } while ((Get-Date) -lt $deadline)
            }
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
        withCredentials([
          string(credentialsId: 'AWS_ACCESS_KEY_ID', variable: 'AWS_ACCESS_KEY_ID'),
          string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY')
        ]) {
          powershell '''
            $ErrorActionPreference = "Continue"
            aws eks update-kubeconfig --name $env:CLUSTER_NAME --region $env:AWS_REGION
            $svcHost = (kubectl get svc nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
            if (-not $svcHost) { Write-Host "Service hostname not ready, skipping ZAP"; exit 0 }
            $url = "http://$svcHost"

            # Pre-pull ZAP image with retries (prefer GHCR, fallback to Docker Hub)
            $zapImageGhcr = "ghcr.io/zaproxy/zaproxy:stable"
            $zapImageHub  = "owasp/zap2docker-stable"
            $pulled = $false
            foreach ($img in @($zapImageGhcr, $zapImageHub)) {
              for ($i=0; $i -lt 2 -and -not $pulled; $i++) {
                try {
                  Write-Host "Pulling ZAP image: $img (attempt $($i+1))"
                  docker pull $img
                  if ($LASTEXITCODE -eq 0) { $pulled = $true; $zapImage = $img }
                } catch { Start-Sleep -Seconds 3 }
              }
              if ($pulled) { break }
            }

            if (-not $pulled) {
              Write-Host "Could not pull any ZAP image; skipping ZAP baseline (non-blocking)."
              exit 0
            }

            # Prepare writable artifacts directory and mount it for report output
            $artDir = Join-Path $env:WORKSPACE "zap-artifacts"
            if (-not (Test-Path $artDir)) { New-Item -ItemType Directory -Path $artDir | Out-Null }
            $artMount = ("$artDir").Replace('\\','/')

            Write-Host "Running ZAP Baseline scan against $url using $zapImage"
            docker run --rm -u 0:0 -v "$($artMount):/zap/wrk" -t $zapImage zap-baseline.py -t $url -r zap.html
            if ($LASTEXITCODE -ne 0) { Write-Host "ZAP baseline returned non-zero ($LASTEXITCODE). Proceeding (non-blocking)."; $global:LASTEXITCODE = 0 }
          '''
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'zap-artifacts/zap.html', allowEmptyArchive: true
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
