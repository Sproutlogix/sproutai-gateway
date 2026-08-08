# 🚀 SproutAI Gateway

> **An In-House, Enterprise-Grade AI Gateway by Sproutlogix**

**SproutAI Gateway** is a self-hosted API gateway designed to unify multi-cloud LLM providers under a single control plane. Deployed 100% inside your private cloud or on-premises network, it provides model routing, application-level cost controls, and enterprise audit capabilities without exposing prompt payloads to third parties.

---

## ✨ Features

* **Universal Multi-Cloud Routing:** Unified OpenAI-compatible API layer supporting **AWS Bedrock**, **Azure AI Foundry**, **OpenAI APIs**, and **Anthropic APIs**.
* **FinOps & Cost Budgeting:** Set app-level monthly spending hard-caps, token quotas, and automated fallback routes.
* **100% Sovereign Deployment:** Runs within your private VPC or Kubernetes cluster via Docker. Zero external telemetry.
* **Purview & Governance Services:** Expandable with Sproutlogix consultancy for native **Microsoft Azure Purview** data lineage, PII redaction, and compliance logging.

---

## 📁 Repository Structure

This public repository contains deployment configurations and setup scripts for running the **SproutAI Gateway** container image (`ghcr.io/sproutlogix/sproutai-gateway:latest`):

```text
.
├── docker-compose.yml     # Container orchestration definition
├── .env.example           # Environment configuration template
├── install.sh             # Automated installer (MySQL setup & .env generator)
└── README.md              # Deployment & usage documentation
```

---

## ⚡ Quickstart (Local / On-Premises Deployment)

### Prerequisites
* Linux / macOS (Ubuntu/Debian recommended for `install.sh`)
* [Docker](https://docs.docker.com/get-docker/) & Docker Compose
* `sudo` / root privileges (if installing local MySQL via `install.sh`)

### Step 1: Clone Repository
```bash
git clone [https://github.com/sproutlogix/sproutai-gateway.git](https://github.com/sproutlogix/sproutai-gateway.git)
cd sproutai-gateway
```

### Step 2: Run Automated Installer
The included `install.sh` script automates local setup by installing MySQL Server, creating a database and user with random 32-character passwords, generating a security pepper, and writing these parameters to `.env`:

```bash
chmod +x install.sh
sudo ./install.sh
```

### Step 3: Configure API Keys
Edit the newly generated `.env` file to add your model provider credentials (e.g., `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `AWS_BEARER_TOKEN_BEDROCK`):

```bash
nano .env
```

### Step 4: Start the Gateway Container
Launch the gateway using Docker Compose:

```bash
docker compose up -d
```

The gateway will start on **`http://localhost:8000`**. You can verify health status by running:
```bash
curl http://localhost:8000/api/health
```

---

## ⚙️ Environment Variables Reference

| Variable Name | Description | Default | Required |
| :--- | :--- | :--- | :--- |
| `ENVIRONMENT` | Deployment mode (`dev`, `production`) | `dev` | Yes |
| `GATEWAY_NAME` | Identifier for the gateway instance | `sprout-ai-gateway` | Yes |
| `MYSQL_HOST` | Database host IP / domain | `localhost` | Yes |
| `MYSQL_PORT` | Database port | `3306` | Yes |
| `MYSQL_DATABASE` | Database name | `sproutai_db` | Yes |
| `MYSQL_USER` | Database username | `sproutai_user` | Yes |
| `MYSQL_PASSWORD` | Database user password | *None* | Yes |
| `API_KEY_HASH_PEPPER` | Secret string for hashing gateway API keys | *None* | Yes |
| `AWS_REGION` | AWS Region for Bedrock calls | `us-east-2` | No |
| `AWS_BEARER_TOKEN_BEDROCK` | AWS Bedrock authentication token | *None* | No |
| `OPENAI_API_KEY` | OpenAI API Secret Key | *None* | No |
| `ANTHROPIC_API_KEY` | Anthropic API Secret Key | *None* | No |
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI Resource Endpoint | *None* | No |
| `AZURE_OPENAI_API_KEY` | Azure OpenAI Key | *None* | No |

---

## ☁️ Cloud Deployment Guides

---

### Option A: AWS ECS (Fargate) Deployment

In AWS ECS, standard non-sensitive settings are passed via task environment variables, while secrets are pulled securely from **AWS Secrets Manager**.

#### 1. Store Secrets in AWS Secrets Manager
Create a secret (e.g., `sproutai/production/secrets`) containing your key-value pairs:
```json
{
  "MYSQL_PASSWORD": "your-db-password",
  "OPENAI_API_KEY": "sk-proj-...",
  "ANTHROPIC_API_KEY": "sk-ant-...",
  "API_KEY_HASH_PEPPER": "your-random-hash-pepper"
}
```

#### 2. Configure IAM Task Execution Role
Grant your `ecsTaskExecutionRole` permission to read secrets:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:us-east-2:123456789012:secret:sproutai/production/secrets-*"
    }
  ]
}
```

#### 3. ECS Task Definition Snippet
```json
{
  "family": "sproutai-gateway-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::123456789012:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "sproutai-gateway",
      "image": "ghcr.io/sproutlogix/sproutai-gateway:latest",
      "essential": true,
      "portMappings": [{ "containerPort": 8000, "hostPort": 8000 }],
      "environment": [
        { "name": "ENVIRONMENT", "value": "production" },
        { "name": "GATEWAY_NAME", "value": "sproutai-prod" },
        { "name": "MYSQL_HOST", "value": "sproutai-rds.cluster-123456789012.us-east-2.rds.amazonaws.com" },
        { "name": "MYSQL_PORT", "value": "3306" },
        { "name": "MYSQL_DATABASE", "value": "sproutai_db" },
        { "name": "MYSQL_USER", "value": "sproutai_user" }
      ],
      "secrets": [
        {
          "name": "MYSQL_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:us-east-2:123456789012:secret:sproutai/production/secrets:MYSQL_PASSWORD::"
        },
        {
          "name": "OPENAI_API_KEY",
          "valueFrom": "arn:aws:secretsmanager:us-east-2:123456789012:secret:sproutai/production/secrets:OPENAI_API_KEY::"
        },
        {
          "name": "ANTHROPIC_API_KEY",
          "valueFrom": "arn:aws:secretsmanager:us-east-2:123456789012:secret:sproutai/production/secrets:ANTHROPIC_API_KEY::"
        },
        {
          "name": "API_KEY_HASH_PEPPER",
          "valueFrom": "arn:aws:secretsmanager:us-east-2:123456789012:secret:sproutai/production/secrets:API_KEY_HASH_PEPPER::"
        }
      ]
    }
  ]
}
```

---

### Option B: Azure App Service Deployment

Azure App Service allows referencing **Azure Key Vault** secrets directly in application environment settings.

#### 1. Store Secrets in Azure Key Vault
Store secret values in Azure Key Vault (`MYSQL-PASSWORD`, `OPENAI-API-KEY`, `ANTHROPIC-API-KEY`, `API-KEY-HASH-PEPPER`).

#### 2. Enable Managed Identity
1. Navigate to your App Service -> **Settings > Identity** and enable **System-assigned Managed Identity**.
2. Assign the **Key Vault Secrets User** role to this identity inside your Azure Key Vault.

#### 3. Map App Settings to Key Vault
In Azure Portal, navigate to App Service -> **Settings > Environment variables > App settings**, and add:

| Setting Name | Configuration Value |
| :--- | :--- |
| `ENVIRONMENT` | `production` |
| `MYSQL_HOST` | `sproutai-db.mysql.database.azure.com` |
| `MYSQL_DATABASE` | `sproutai_db` |
| `MYSQL_USER` | `sproutai_user` |
| `MYSQL_PASSWORD` | `@Microsoft.KeyVault(VaultName=my-keyvault;SecretName=MYSQL-PASSWORD)` |
| `OPENAI_API_KEY` | `@Microsoft.KeyVault(VaultName=my-keyvault;SecretName=OPENAI-API-KEY)` |
| `ANTHROPIC_API_KEY` | `@Microsoft.KeyVault(VaultName=my-keyvault;SecretName=ANTHROPIC-API-KEY)` |
| `API_KEY_HASH_PEPPER` | `@Microsoft.KeyVault(VaultName=my-keyvault;SecretName=API-KEY-HASH-PEPPER)` |

---

## 💼 Sproutlogix Enterprise Consultancy & Services

The SproutAI Gateway container is **100% free for commercial use**. For enterprise organizations requiring tailored integration, Sproutlogix offers professional advisory and engineering services:

* **Azure Purview Governance:** Automated prompt data lineage, audit logging, and custom sensitivity cataloging.
* **Custom Gateway Plugins:** Proprietary middleware development, token rate limiting rules, and internal SSO/OAuth2 integrations.
* **Private RAG & Fine-Tuning:** In-house vector database deployment, pipeline construction, and enterprise security reviews.

📧 **Get in touch:** [https://sproutlogix.com](https://sproutlogix.com)

---

## 📜 License

SproutAI Gateway Community Edition is distributed under the **Apache 2.0 License**.
