# Intelligent Secure CI/CD Control Plane with AI Risk Scoring

A production-grade, end-to-end CI/CD control plane that combines **DevSecOps best practices** with **machine learning-driven risk scoring** to intelligently gate deployments based on code quality, security posture, and predicted failure probability.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Developer Workflow                           │
│  git push → GitHub → Jenkins Pipeline → AI Risk Gate → ArgoCD      │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
          ┌────────────────────▼─────────────────────┐
          │           Jenkins Pipeline               │
          │  ┌──────────────────────────────────┐   │
          │  │  Build → Test → SAST → SCA       │   │
          │  │  → Container Scan → SBOM         │   │
          │  │  → AI Risk Score → Security Gate │   │
          │  │  → Push ECR → Sign → GitOps Sync│   │
          │  └──────────────────────────────────┘   │
          └──────────┬───────────────────────────────┘
                     │
     ┌───────────────▼──────────────────────────┐
     │          AWS EKS Cluster                 │
     │  ┌──────────┐  ┌──────────┐  ┌────────┐ │
     │  │ ArgoCD   │  │  OPA     │  │  App   │ │
     │  │ (GitOps) │  │Gatekeeper│  │  Pods  │ │
     │  └──────────┘  └──────────┘  └────────┘ │
     └──────────────────────────────────────────┘
```

## Tech Stack

| Component            | Technology                                |
|----------------------|-------------------------------------------|
| CI/CD Orchestration  | Jenkins (Kubernetes agents)               |
| Container Registry   | AWS ECR (immutable tags, scan-on-push)    |
| GitOps               | ArgoCD                                    |
| Static Analysis      | SonarQube                                 |
| SCA / Container Scan | Snyk                                      |
| SBOM Generation      | Syft (SPDX JSON format)                   |
| Image Signing        | Cosign (keyless via Sigstore)             |
| Policy Enforcement   | OPA Gatekeeper                            |
| AI Risk Scoring      | Python + scikit-learn (Gradient Boosting) |
| Infrastructure       | Terraform (AWS EKS, ECR, VPC, IRSA)      |
| Observability        | Prometheus + Grafana + CloudWatch         |
| App Framework        | Flask + Gunicorn                          |

## Repository Structure

```
├── app/                    # Sample microservice application
│   ├── src/                # Application source code
│   ├── tests/              # Unit tests
│   ├── Dockerfile          # Multi-stage secure Docker build
│   ├── requirements.txt
│   └── sonar-project.properties
│
├── ci/                     # CI/CD pipeline definitions
│   ├── jenkins/
│   │   ├── Jenkinsfile     # Declarative pipeline
│   │   ├── config/         # Jenkins Helm values
│   │   └── shared-library/ # Reusable pipeline steps
│   └── scripts/            # SBOM and GitOps update scripts
│
├── gitops/                 # GitOps manifests (ArgoCD + Helm)
│   ├── argocd/             # ArgoCD application definitions
│   ├── helm-charts/        # Helm chart for sample-app
│   └── kustomize/          # Kustomize overlays (dev/prod)
│
├── infra/                  # Infrastructure as Code
│   └── terraform/          # Terraform modules (VPC, EKS, ECR, IRSA)
│
├── ml-risk/                # AI Risk Scoring engine
│   ├── data/               # Synthetic training dataset
│   ├── src/                # Model training, inference, features
│   ├── models/             # Saved model artifacts
│   └── tests/              # Model tests
│
├── observability/          # Monitoring and alerting
│   ├── prometheus/         # Prometheus config + alert rules
│   ├── grafana/            # Dashboards + values
│   └── cloudwatch/         # Log Insights queries
│
└── security/               # Security tooling
    ├── cosign/             # Image signing scripts
    ├── opa/                # OPA Gatekeeper templates + constraints
    └── snyk/               # Snyk ignore policies
```

## Pipeline Stages

```
Checkout → Build → Unit Tests → SonarQube → Quality Gate
  → Snyk SCA → Container Build → Snyk Container Scan
  → SBOM Generation → AI Risk Scoring → Security Gates Decision
  → Push to ECR → Sign Image (Cosign) → Update GitOps Repo
  → ArgoCD Sync
```

### AI Risk Scoring

The ML model (`ml-risk/`) predicts pipeline failure probability using features such as:

- `changed_files` — number of files modified
- `code_coverage` — test coverage percentage
- `critical_vulns` — critical CVEs found by Snyk
- `commit_message_length` — commit message quality proxy
- `build_history_failures` — recent failure rate
- `hour_of_day` / `day_of_week` — temporal risk signals
- `author_experience` — commit history depth

**Risk Levels:**
- 🟢 `LOW` — score < 0.3 → auto-deploy
- 🟡 `MEDIUM` — score 0.3–0.7 → deploy with warning
- 🔴 `HIGH` — score ≥ 0.7 → human approval required

## Prerequisites

- AWS account with appropriate IAM permissions
- `terraform` >= 1.6
- `kubectl` + `helm` >= 3.12
- `python` >= 3.11
- `docker` >= 24
- Jenkins operator installed on EKS
- ArgoCD installed on EKS

## Quick Start

### 1. Infrastructure Provisioning

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

### 2. Train the Risk Model

```bash
cd ml-risk
pip install -r requirements.txt
python data/generate_dataset.py
python src/train.py
```

### 3. Deploy Jenkins + ArgoCD

```bash
# Install Jenkins via Helm
helm repo add jenkins https://charts.jenkins.io
helm install jenkins jenkins/jenkins \
  -f ci/jenkins/config/jenkins-values.yaml \
  -n jenkins --create-namespace

# Install ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  -f gitops/argocd/install/argocd-values.yaml \
  -n argocd --create-namespace
```

### 4. Apply OPA Gatekeeper Policies

```bash
# Install Gatekeeper
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.14/deploy/gatekeeper.yaml

# Apply templates and constraints
kubectl apply -f security/opa/templates/
kubectl apply -f security/opa/constraints/
```

### 5. Set up Observability

```bash
# Prometheus stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  -f observability/prometheus/prometheus-values.yaml \
  -n monitoring --create-namespace

# Grafana (included in kube-prometheus-stack or standalone)
helm install grafana grafana/grafana \
  -f observability/grafana/grafana-values.yaml \
  -n monitoring
```

### 6. Generate Cosign Key Pair

```bash
chmod +x security/cosign/cosign-key-pair.sh
./security/cosign/cosign-key-pair.sh
```

### Using the Makefile

```bash
make help          # Show all targets
make test          # Run unit tests
make train-model   # Train risk scoring model
make infra-plan    # Terraform plan
make infra-apply   # Terraform apply
make opa-apply     # Apply OPA policies
make sbom          # Generate SBOM for latest image
```

## Security Controls

| Control                    | Tool            | Enforcement          |
|----------------------------|-----------------|----------------------|
| SAST                       | SonarQube       | Quality Gate         |
| SCA (dependencies)         | Snyk            | Severity threshold   |
| Container image scan       | Snyk            | Critical block       |
| Image signing              | Cosign/Sigstore | Admission webhook    |
| Registry allowlist         | OPA Gatekeeper  | Admission deny       |
| No latest tag              | OPA Gatekeeper  | Admission deny       |
| No privileged containers   | OPA Gatekeeper  | Admission deny       |
| Non-root enforcement       | OPA Gatekeeper  | Admission deny       |
| Resource limits required   | OPA Gatekeeper  | Admission deny       |
| SBOM attestation           | Syft + Cosign   | Artifact archive     |

## Observability

- **Prometheus** scrapes Jenkins, app `/metrics`, and ArgoCD
- **Grafana** dashboards:
  - `CI/CD Pipeline Metrics` — success rate, build duration, failure reasons
  - `Risk Scoring` — risk score trends, model predictions
  - `Security Gates` — coverage trends, vulnerability counts, gate pass rate
- **CloudWatch Logs Insights** — EKS control plane audit, application error analysis

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Ensure all security gates pass locally (`make test`)
4. Submit a Pull Request — the pipeline will auto-score risk

## License

MIT
