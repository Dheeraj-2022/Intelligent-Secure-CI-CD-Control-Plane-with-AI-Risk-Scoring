.PHONY: help test test-ml train-model generate-dataset \
        infra-init infra-plan infra-apply infra-destroy \
        opa-apply opa-delete docker-build docker-push \
        sbom cosign-setup argocd-sync clean

# ─────────────────────────────────────────────
# Variables
# ─────────────────────────────────────────────
APP_NAME       ?= sample-app
AWS_REGION     ?= us-west-2
AWS_ACCOUNT_ID ?= $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null)
IMAGE_TAG      ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "latest")
ECR_REGISTRY   ?= $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
NAMESPACE      ?= default
PYTHON         ?= python3
PIP            ?= pip3

# ─────────────────────────────────────────────
# Help
# ─────────────────────────────────────────────
help: ## Show this help message
	@echo ""
	@echo "  Intelligent Secure CI/CD Control Plane — Makefile"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-28s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ─────────────────────────────────────────────
# Application
# ─────────────────────────────────────────────
install: ## Install app Python dependencies
	cd app && $(PIP) install --user -r requirements.txt
	cd app && $(PIP) install --user pytest pytest-cov

test: ## Run application unit tests with coverage
	cd app && $(PYTHON) -m pytest tests/ \
		--cov=src \
		--cov-report=term-missing \
		--cov-report=xml:coverage.xml \
		--junitxml=test-results.xml \
		-v

test-ml: ## Run ML risk model unit tests
	cd ml-risk && $(PYTHON) -m pytest tests/ -v

generate-dataset: ## Generate synthetic training dataset
	cd ml-risk && $(PYTHON) data/generate_dataset.py

train-model: generate-dataset ## Train the AI risk scoring model
	cd ml-risk && $(PIP) install --user -r requirements.txt
	cd ml-risk && $(PYTHON) src/train.py
	@echo "✅ Model saved to ml-risk/models/"

run-app: ## Run the Flask app locally
	cd app && $(PYTHON) src/main.py

# ─────────────────────────────────────────────
# Docker
# ─────────────────────────────────────────────
docker-build: ## Build Docker image
	docker build \
		-t $(ECR_REGISTRY)/$(APP_NAME):$(IMAGE_TAG) \
		-t $(ECR_REGISTRY)/$(APP_NAME):latest \
		--label "git.commit=$(IMAGE_TAG)" \
		app/

docker-push: docker-build ## Build and push image to ECR
	aws ecr get-login-password --region $(AWS_REGION) | \
		docker login --username AWS --password-stdin $(ECR_REGISTRY)
	docker push $(ECR_REGISTRY)/$(APP_NAME):$(IMAGE_TAG)
	docker push $(ECR_REGISTRY)/$(APP_NAME):latest
	@echo "✅ Pushed $(ECR_REGISTRY)/$(APP_NAME):$(IMAGE_TAG)"

# ─────────────────────────────────────────────
# SBOM & Image Signing
# ─────────────────────────────────────────────
sbom: ## Generate SBOM for the latest built image
	@command -v syft >/dev/null 2>&1 || \
		(curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin)
	syft $(ECR_REGISTRY)/$(APP_NAME):$(IMAGE_TAG) \
		-o spdx-json > sbom-$(IMAGE_TAG).json
	@echo "✅ SBOM written to sbom-$(IMAGE_TAG).json"

cosign-setup: ## Generate Cosign key pair and store in Kubernetes secret
	chmod +x security/cosign/cosign-key-pair.sh
	./security/cosign/cosign-key-pair.sh

cosign-sign: ## Sign container image with Cosign
	cosign sign --key k8s://jenkins/cosign-keys \
		$(ECR_REGISTRY)/$(APP_NAME):$(IMAGE_TAG)

cosign-verify: ## Verify container image signature
	cosign verify --key k8s://jenkins/cosign-keys \
		$(ECR_REGISTRY)/$(APP_NAME):$(IMAGE_TAG)

# ─────────────────────────────────────────────
# Infrastructure (Terraform)
# ─────────────────────────────────────────────
infra-init: ## Terraform init
	cd infra/terraform && terraform init

infra-plan: infra-init ## Terraform plan
	cd infra/terraform && terraform plan -var-file=terraform.tfvars

infra-apply: infra-init ## Terraform apply
	cd infra/terraform && terraform apply -var-file=terraform.tfvars -auto-approve

infra-destroy: ## Terraform destroy (DANGER!)
	cd infra/terraform && terraform destroy -var-file=terraform.tfvars

infra-output: ## Show Terraform outputs
	cd infra/terraform && terraform output

# ─────────────────────────────────────────────
# OPA Gatekeeper Policies
# ─────────────────────────────────────────────
opa-apply: ## Apply OPA Gatekeeper templates and constraints
	kubectl apply -f security/opa/templates/
	@echo "Waiting for ConstraintTemplates to be ready..."
	sleep 5
	kubectl apply -f security/opa/constraints/
	@echo "✅ OPA policies applied"

opa-delete: ## Delete OPA policies
	kubectl delete -f security/opa/constraints/ --ignore-not-found
	kubectl delete -f security/opa/templates/ --ignore-not-found

opa-status: ## Check OPA constraint status
	kubectl get constraints
	kubectl describe K8sDisallowLatestTag disallow-latest-image-tag
	kubectl describe K8sRequireResources require-resource-limits

# ─────────────────────────────────────────────
# ArgoCD / GitOps
# ─────────────────────────────────────────────
argocd-install: ## Install ArgoCD via Helm
	helm repo add argo https://argoproj.github.io/argo-helm
	helm repo update
	helm install argocd argo/argo-cd \
		-f gitops/argocd/install/argocd-values.yaml \
		-n argocd --create-namespace

argocd-app-of-apps: ## Deploy App-of-Apps pattern to ArgoCD
	kubectl apply -f gitops/argocd/applications/app-of-apps.yaml

argocd-sync: ## Force sync sample-app ArgoCD application
	argocd app sync $(APP_NAME)-dev --prune
	argocd app wait $(APP_NAME)-dev --health

# ─────────────────────────────────────────────
# Jenkins
# ─────────────────────────────────────────────
jenkins-install: ## Install Jenkins via Helm
	helm repo add jenkins https://charts.jenkins.io
	helm repo update
	helm install jenkins jenkins/jenkins \
		-f ci/jenkins/config/jenkins-values.yaml \
		-n jenkins --create-namespace

jenkins-password: ## Get Jenkins admin password
	kubectl get secret jenkins -n jenkins \
		-o jsonpath="{.data.jenkins-admin-password}" | base64 --decode; echo

# ─────────────────────────────────────────────
# Observability
# ─────────────────────────────────────────────
monitoring-install: ## Install kube-prometheus-stack
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm install prometheus prometheus-community/kube-prometheus-stack \
		-f observability/prometheus/prometheus-values.yaml \
		-n monitoring --create-namespace

grafana-password: ## Get Grafana admin password
	kubectl get secret prometheus-grafana -n monitoring \
		-o jsonpath="{.data.admin-password}" | base64 --decode; echo

# ─────────────────────────────────────────────
# Risk Scoring (local run)
# ─────────────────────────────────────────────
risk-score: ## Run risk scoring inference with sample data
	cd ml-risk && $(PYTHON) src/inference.py \
		--build-number 1 \
		--commit $(IMAGE_TAG) \
		--changed-files 5 \
		--commit-message "feat: add new endpoint JIRA-123" \
		--coverage 85.5 \
		--critical-vulns 0 \
		--output /tmp/risk-score.json
	@echo "✅ Risk score written to /tmp/risk-score.json"
	@cat /tmp/risk-score.json

# ─────────────────────────────────────────────
# Clean
# ─────────────────────────────────────────────
clean: ## Clean build artifacts
	find app/ -name "*.pyc" -delete
	find app/ -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	find ml-risk/ -name "*.pyc" -delete
	find ml-risk/ -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	rm -f app/coverage.xml app/test-results.xml
	rm -f sbom-*.json
	@echo "✅ Clean complete"
