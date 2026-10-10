## Step 1: Create the state bucket (only if it doesn't exist)

```powershell
cd Secret-Manager\bootstrap
terraform init
terraform apply -var="state_bucket_name=ekslab-tfstate-2026"
```
Type `yes`. Note the outputs `state_bucket` and `lock_table`. The lock table defaults to `terraform-locks`.

## Step 2: Add the ECR repo to the main stack

The Secret-Manager stack has no ECR repo, so copy it in from the app project before applying:
```powershell
cd ..\main
copy ..\..\deploy-app\terraform-addition\ecr.tf .
```
Then open `ecr.tf` and add `force_delete = true` to the repository so `terraform destroy` works even when it contains images:
```hcl
resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  ...
```

## Step 3: Apply the main stack

```powershell
terraform init `
  -backend-config="bucket=ekslab-tfstate-2026" `
  -backend-config="region=us-east-1" `
  -backend-config="dynamodb_table=terraform-locks"

$env:TF_VAR_db_password = "SomeStrongPassword123!"
cp terraform.tfvars.example terraform.tfvars
terraform apply
```
- Use your real bucket name in `-backend-config`.
- Set `create_read_replica = false` in `terraform.tfvars` if you want to save RDS hours.
- This takes 15-20 minutes. Rotation of the DB password starts automatically at the end.

If apply fails on the rotation step, add this `depends_on` to the `aws_secretsmanager_secret_rotation` resource in `rotation.tf` and re-run `terraform apply`:
```hcl
depends_on = [
  aws_secretsmanager_secret_version.db_credentials,
  aws_vpc_endpoint.secretsmanager,
  aws_security_group_rule.rds_from_rotation_lambda,
]
```

## Step 4: Connect kubectl

```powershell
terraform output -raw configure_kubectl     # run the command it prints
kubectl get nodes                           # wait for Ready
```

## Step 5: Build and push the app image

```powershell
$repo = terraform output -raw ecr_repo_url
$registry = $repo.Split("/")[0]

$pw = aws ecr get-login-password --region us-east-1
docker login --username AWS --password $pw $registry

cd ..\..\deploy-app\app
docker build -t "${repo}:latest" .
docker push "${repo}:latest"
```
Docker Desktop must be running. The `$repo` variable avoids the account-ID typo from last time. If you changed folders, run `$repo = ...` again from `main`.

## Step 6: Install External Secrets Operator

The Secret-Manager stack rotates the DB password, so the app should read credentials from Secrets Manager through ESO, not a hand-made secret. Go back to `main` for the role ARN:

```powershell
cd ..\..\Secret-Manager\main
$roleArn = terraform output -raw eso_role_arn

@"
serviceAccount:
  create: true
  name: external-secrets-sa
  annotations:
    eks.amazonaws.com/role-arn: $roleArn
"@ | Set-Content eso-values.yaml

helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace -f eso-values.yaml
kubectl get pods -n external-secrets       # wait until all Running
```
The namespace `external-secrets` and ServiceAccount `external-secrets-sa` must stay exactly as written, because the IAM trust policy checks them.

## Step 7: Create the store and the secret mapping

```powershell
@'
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: aws-sm
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
'@ | kubectl apply -f -

@'
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: db-credentials
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: aws-sm
    kind: ClusterSecretStore
  target:
    name: db-credentials
  data:
    - secretKey: DB_HOST
      remoteRef: { key: eks-postgres-lab/db-credentials, property: host }
    - secretKey: DB_NAME
      remoteRef: { key: eks-postgres-lab/db-credentials, property: dbname }
    - secretKey: DB_USER
      remoteRef: { key: eks-postgres-lab/db-credentials, property: username }
    - secretKey: DB_PASSWORD
      remoteRef: { key: eks-postgres-lab/db-credentials, property: password }
'@ | kubectl apply -f -

kubectl get externalsecret          # wait for STATUS: SecretSynced
kubectl get secret db-credentials
```
If the CRD version is rejected, replace `external-secrets.io/v1` with `external-secrets.io/v1beta1` in both files. Do **not** create `db-credentials` manually with `kubectl create secret`, since ESO owns it now.

## Step 8: Deploy the app

```powershell
cd ..\..\deploy-app
(Get-Content k8s\deployment.yaml) -replace 'REPLACE_ME_ECR_REPO_URL', $repo | Set-Content k8s\deployment.yaml

kubectl apply -f k8s\deployment.yaml
kubectl apply -f k8s\service.yaml

kubectl get pods -w                  # wait for demo-app Running 1/1
kubectl get svc demo-app -w          # wait for EXTERNAL-IP (1-2 min)
```

## Step 9: Test

```powershell
curl http://<EXTERNAL-IP>/health
curl http://<EXTERNAL-IP>/db-check
```
`/db-check` should return `{"status":"connected","postgres_version":"PostgreSQL 16..."}`. The DNS name of a new ELB can take a minute or two to resolve.

## Step 10 (optional): See rotation work

```powershell
aws secretsmanager rotate-secret --secret-id eks-postgres-lab/db-credentials --region us-east-1
```
After about a minute, the k8s Secret updates. Running pods keep the old password until restarted:
```powershell
kubectl rollout restart deployment demo-app
curl http://<EXTERNAL-IP>/db-check
```

## Troubleshooting quick list
- **Pod `CreateContainerConfigError`:** the ExternalSecret hasn't synced yet. Check `kubectl describe externalsecret db-credentials`. Common causes are the wrong role ARN or a wrong ServiceAccount name.
- **`ImagePullBackOff`:** the image wasn't pushed, or `deployment.yaml` still has the placeholder or a mistyped URL.
- **`password authentication failed` after rotation:** restart the deployment so the pod reads the new secret.

When you're done, tear down in this order: delete the Service (`kubectl delete -f k8s\service.yaml`, which removes the ELB), delete the deployment, `externalsecret` and `secretstore`, then `helm uninstall external-secrets -n external-secrets`, and finally `terraform destroy` in `main`.