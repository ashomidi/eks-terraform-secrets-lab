# EKS + RDS Postgres Lab (Terraform, AWS Free Tier)

Two stacks:
- `bootstrap/` -- creates the S3 bucket + DynamoDB table Terraform uses for remote
  state. Apply this **once**, keep it running across sessions (it costs pennies).
- `main/` -- the actual EKS cluster + RDS Postgres (main + read replica). This is
  the one you create-and-destroy every practice session.

## Cost notes (read before applying)
- EKS control plane: flat **$0.10/hr**, not free-tier eligible. Destroy `main/`
  when you're done for the day.
- `t3.small` worker node: small hourly cost, not covered by the free-tier micro
  instance hours.
- RDS `db.t3.micro`: free tier gives 750 combined instance-hours/month across
  all your RDS instances -- running main + replica together uses that allowance
  twice as fast. Set `create_read_replica = false` while you're just practicing
  EKS/K8s basics, flip it to `true` when you specifically want to practice
  replication.
- No NAT Gateway is created (worker nodes sit in public subnets instead) --
  that alone saves ~$0.045/hr + data charges.

## Prerequisites
- AWS CLI configured (`aws configure`) with a user that has admin-ish access
  for EKS/RDS/VPC/IAM (a lab account, not production).
- Terraform >= 1.5, `kubectl`, on PATH (Windows: via Chocolatey or direct download).

## 1. Bootstrap (once)

```powershell
cd bootstrap
terraform init
terraform apply -var="state_bucket_name=<pick-a-globally-unique-name>"
```

Note the two outputs: `state_bucket` and `lock_table`. You'll reuse these for
every stack going forward, including your secrets-rotation lab.

## 2. Main stack

```powershell
cd ../main
terraform init `
  -backend-config="bucket=<state_bucket from step 1>" `
  -backend-config="region=us-east-1" `
  -backend-config="dynamodb_table=<lock_table from step 1>"

$env:TF_VAR_db_password = "SomeStrongPassword123!"
cp terraform.tfvars.example terraform.tfvars   # edit as you like

terraform apply
```

This takes 10-15 minutes (EKS control plane provisioning is slow -- normal).

## 3. Connect kubectl

```powershell
terraform output configure_kubectl   # prints the exact command, run it
kubectl get nodes                    # should show your node(s) as Ready
```

## 4. Practice deploying something
Once nodes are `Ready`, you're ready for the next phase: deploying a
containerized app (Deployment + Service + Ingress) that talks to
`db_main_endpoint`. Ask me and we'll build that next.

## 5. Tear down (every session)

```powershell
cd main
terraform destroy
```

Leave `bootstrap/` alone -- it's cheap to keep and saves you from re-creating
a state bucket every time. Only destroy `bootstrap/` when you're completely
done with all your Terraform labs.

## Known simplification vs. production
Worker nodes are in public subnets (no NAT Gateway) to keep this free-tier
friendly. In a real production setup you'd put nodes in private subnets behind
a NAT Gateway or NAT instance. Worth knowing the difference, not worth paying
for in a personal lab.
