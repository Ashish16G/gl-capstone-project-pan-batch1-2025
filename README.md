# Capstone: Jenkins → Terraform → EKS (with ECR and Docker)

This repository delivers a simple web app (Nginx + static UI) through a CI/CD pipeline:
- Build Docker image → push to Amazon ECR
- Provision infra with Terraform → Amazon EKS (cluster, node group, VPC)
- Deploy to EKS via Jenkins stages

## Architecture
- Jenkins Pipeline builds and pushes image to ECR
- Terraform manages VPC, EKS, IAM, and related resources
- Kubernetes manifests deploy the app, exposed by a LoadBalancer Service

## Prerequisites
- AWS account with permissions for ECR/EKS/VPC/IAM (AdministratorAccess recommended for demo)
- Jenkins (Windows agent supported) with AWS CLI, Terraform, kubectl, and Docker installed
- Git credentials for this repository

## Jenkins setup
1. Create two Global “Secret text” credentials:
   - ID: `AWS_ACCESS_KEY_ID`  → value: your AWS access key ID
   - ID: `AWS_SECRET_ACCESS_KEY` → value: your AWS secret access key
2. Create a Pipeline job pointing to this repo (Pipeline script from SCM)
3. Ensure the job uses `Jenkinsfile` (default path)

## Pipeline parameters
- `AWS_REGION` (default: `ap-south-1`)
- `ECR_REPO` (default: `gl-capactone-project-pan-repo`)
- `CLUSTER_NAME` (default: `capstone-eks`)

## How to run
1. Run the Jenkins job with defaults
2. Stages executed:
   - Checkout
   - Tools Versions
   - AWS Identity Check (sanity check)
   - Terraform Init/Plan/Apply (creates/updates VPC, EKS, etc.)
   - Docker Build and Push (builds and pushes image to ECR)
   - Deploy to EKS (applies manifests)
   - Rollout ECR Image (updates deployment to the new tag and waits for rollout)
3. After success, get Service External IP:
   ```
   kubectl get svc nginx-service -o wide
   ```
   Open `http://<EXTERNAL-IP>` in the browser

## Local kubectl context
Set kubeconfig to your cluster (if testing locally):
```
aws eks update-kubeconfig --name capstone-eks --region ap-south-1
```

## App UI
- Page title: “GL-Capstone-Project-PAN-2025” with a subtle white underline
- Theme: Indian flag-inspired gradient (saffron → dark → green) with cohesive component colors
- Calculator: display + keypad in one block, with the history panel on the right (stacks below on small screens)
- Operators and behavior: +, −, ×, ÷, %, decimals, C, backspace, Enter (=), and keyboard input
- Equals button: spans the full row on all screen sizes
- Touch-friendly: larger buttons and spacing; responsive adjustments for coarse pointers
- History: shows the last few results, clickable to reuse; includes a “Clear” button; shows “No history yet” placeholder when empty
- Badge: reads “GlobalLogic Calculator” (removed previous badges/diagram section for a cleaner look)

## Cost notes
- ELB and NAT Gateway incur charges while running
- To lower costs without removing infra:
  - Delete Service: `kubectl delete svc nginx-service`
  - Scale deployment to 0: `kubectl scale deploy nginx-deployment --replicas=0`
  - Scale node group to 0 instances (managed node group):
    ```
    aws eks update-nodegroup-config \
      --cluster-name capstone-eks \
      --nodegroup-name capstone-nodes \
      --scaling-config minSize=0,desiredSize=0,maxSize=1 \
      --region ap-south-1
    ```

## Destroy capability
- The pipeline’s destroy capability has been disabled deliberately to prevent accidental deletion
- `Jenkinsfile.destroy` is a no-op and exits with an error if triggered
- If you need full teardown later, consider switching Terraform backend to S3 and running `terraform destroy` manually from `infra/`

## Troubleshooting
- ECR login 400/“no basic auth credentials” → verify credentials, region, time sync, and proxy rules
- OIDC thumbprint errors → ensure full issuer URL is used by Terraform (handled in this repo)
- Rollout timeouts → check `kubectl describe` for ImagePullBackOff, readiness, or capacity issues

## Maintainers
Piyush, Ashish, and Neha
