# 🚀 Sprout AI Gateway

> **An In-House, Enterprise-Grade AI Gateway by Sproutlogix**

**Sprout AI Gateway** is a self-hosted API gateway designed to unify multi-cloud LLM providers under a single control plane. Deployed 100% inside your private cloud or on-premises network, it provides model routing, application-level cost controls, and enterprise audit capabilities without exposing prompt payloads to third parties.

The API and the management web UI ship as **one Docker container**. The only other thing it needs is a MySQL database, which the included `docker-compose.yml` runs for you.

---

## ✨ Features

* **Universal Multi-Cloud Routing:** OpenAI-compatible and Anthropic-compatible API layers supporting **AWS Bedrock**, **Azure AI Foundry**, **OpenAI APIs**, and **Anthropic APIs**.
* **Custom Applications:** Use the official OpenAI and Anthropic SDKs from your own code by changing only the base URL and key.
* **Claude Code & CLI Support:** Point Claude Code, aider, `llm`, LangChain or the official SDKs at the gateway. Claude models are passed through natively (streaming, tool use, thinking, prompt caching).
* **Built-in Login & Roles:** Admin and regular users with no external identity provider. Regular users only see usage for the API keys they own.
* **FinOps & Cost Budgeting:** Per-key monthly budgets and token limits, with optional hard caps. Usage cost includes prompt caching.
* **Custom Usage Reports:** Admins filter cost and token usage by team, owner, API key, model, date range and more, group it any way they like, and export it to Excel or CSV.
* **Usage Alerts & Daily Summaries:** Email the owners of an API key when it reaches 80%, 90% or 100% of its budget or token limit, with thresholds and on/off set per key. Users can also get a daily usage summary.
* **100% Sovereign Deployment:** Runs within your private VPC or Kubernetes cluster via Docker. Zero external telemetry.
* **Purview & Governance Services:** Expandable with Sproutlogix consultancy for native **Microsoft Azure Purview** data lineage, PII redaction, and compliance logging.

---

## 📁 Repository Structure

This public repository contains deployment configurations and setup scripts for running the **Sprout AI Gateway** container image (`ghcr.io/sproutlogix/ai_gateway_core:latest`):

```text
.
├── docker-compose.yml     # Gateway + MySQL container definition
├── .env.example           # Environment configuration template
├── install.sh             # Automated installer (generates secrets & admin login, writes .env)
└── README.md              # Deployment & usage documentation
```

---

## ⚡ Quickstart (Local / On-Premises Deployment)

### Prerequisites
* Linux / macOS (Ubuntu/Debian recommended for `install.sh`)
* [Docker](https://docs.docker.com/get-docker/) & Docker Compose
* `sudo` / root privileges (only if you use `install.sh`)

### Step 1: Clone Repository
```bash
git clone https://github.com/Sproutlogix/ai-gateway.git
cd ai-gateway
```

### Step 2: Create your `.env`
**Option A: automated installer (Ubuntu/Debian).** `install.sh` generates random database credentials, a security pepper and the first admin password, and writes them to `.env`. It also installs MySQL Server on the host. You don't need that MySQL for `docker compose`, which runs its own database.

```bash
chmod +x install.sh
sudo ./install.sh
```

**Option B: by hand.**
```bash
cp .env.example .env
```
Then set at least `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`, `API_KEY_HASH_PEPPER` (a long random string), `ADMIN_EMAIL` and `ADMIN_PASSWORD` (at least 10 characters). One way to generate secrets is `openssl rand -hex 32`.

### Step 3: Add model provider credentials
Edit `.env` to add your provider credentials (e.g., `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `AWS_BEARER_TOKEN_BEDROCK`). To send usage alert emails, also fill in the `SMTP_*` settings.

```bash
nano .env
```

### Step 4: Start the Gateway
```bash
docker compose up -d
```

The gateway starts on **`http://localhost:8000`**. Check its health with:
```bash
curl http://localhost:8000/health
```

### Step 5: Sign in
Open **http://localhost:8000** and sign in with `ADMIN_EMAIL` / `ADMIN_PASSWORD`. Change the password from the user menu. The admin account is only created on first start, when there are no users. Changing `ADMIN_PASSWORD` later has no effect.

As an admin:
1. **Add model routes** (Dashboard → Model Routes & Pricing), for example `claude-sonnet-5-5` → provider `anthropic`. Set input and output prices per 1M tokens, and optionally cache read and cache write prices (blank = 0.1× and 1.25× the input price for Anthropic and Bedrock, the input price for other providers).
2. **Add users** (Users tab) as *Admin* or *User*.
3. **Create API keys** (Dashboard → API Keys). Set owners, owner emails, budget, token limit and alerts. The key is shown once.

---

## 👥 Users & Roles

Login is built into the gateway. Passwords are hashed with PBKDF2-SHA256 and sessions are stored in MySQL. No third-party identity provider is used.

| Role  | Can do |
| :--- | :--- |
| **Admin** | Everything: users, API keys and their owners, model routes, notifications, reports, and usage for all keys. |
| **User**  | Sees dashboards and budgets **only for the API keys they own**, and the Help pages (Claude Code & CLI, API & SDKs, Contact Sproutlogix). Can change their own password. |

* Accounts lock for 15 minutes after 5 failed sign-ins (`MAX_FAILED_LOGINS`, `LOGIN_LOCKOUT_MINUTES`). Admins can unlock them from the Users tab.
* Locked out of the admin account? Run these inside the container:
  ```bash
  docker exec -it sproutai-gateway python -m app.manage reset-password --email admin@example.com
  docker exec -it sproutai-gateway python -m app.manage create-user --email you@example.com --admin
  docker exec -it sproutai-gateway python -m app.manage list-users
  ```

---

## 🤖 Using Claude Code and other CLIs

The **Help → Claude Code & CLI** page in the web UI generates a ready-to-paste setup from your model routes. For example:

```bash
export ANTHROPIC_BASE_URL="http://localhost:8000/anthropic"
export ANTHROPIC_AUTH_TOKEN="<your-gateway-api-key>"
export ANTHROPIC_MODEL="claude-sonnet-5-5"
export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-5-5"
export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet-5-5"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-haiku-4-5"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
# Only if your Claude routes use Amazon Bedrock:
export CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1
claude
```

* Name Claude routes after real Claude model IDs (for example `claude-sonnet-5-5`). Claude Code uses the name to size its context window.
* Every model Claude Code uses, including the Haiku model for background tasks, must be routed and allowed on the API key.
* If you previously signed in to Claude Code with a Claude account, run `/logout` in Claude Code first.

Other tools:
```bash
# OpenAI-compatible tools (aider, llm, LangChain, ...)
export OPENAI_BASE_URL="http://localhost:8000/openai/v1"
export OPENAI_API_KEY="<your-gateway-api-key>"

# Anthropic SDKs
export ANTHROPIC_BASE_URL="http://localhost:8000/anthropic"
export ANTHROPIC_API_KEY="<your-gateway-api-key>"
```

---

## 🧩 Using the gateway in your own application

Use the official OpenAI or Anthropic SDKs and change only the base URL and API key. The **Help → API & SDKs** page in the web UI has copy-ready Python, Node.js and cURL samples with your gateway's URL and model names filled in.

| API | SDK base URL | Endpoints |
| :--- | :--- | :--- |
| OpenAI | `https://your-gateway/openai/v1` | `/chat/completions`, `/embeddings`, `/models` |
| Anthropic | `https://your-gateway/anthropic` | `/v1/messages`, `/v1/messages/count_tokens`, `/v1/models` |

```python
import os
from openai import OpenAI
import anthropic

openai_client = OpenAI(base_url="https://your-gateway/openai/v1", api_key=os.environ["GATEWAY_API_KEY"])
reply = openai_client.chat.completions.create(
    model="claude-sonnet",  # a model route name on the gateway
    messages=[{"role": "user", "content": "Hello"}],
    user="jane@example.com",  # optional: "End user" in Reports
)

claude = anthropic.Anthropic(base_url="https://your-gateway/anthropic", api_key=os.environ["GATEWAY_API_KEY"])
message = claude.messages.create(
    model="claude-sonnet",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello"}],
    metadata={"user_id": "jane@example.com"},  # optional: "End user" in Reports
)
```

* **Model names** are the gateway's model routes, not provider model IDs. List them with `GET /openai/v1/models`.
* **Anthropic API:** Claude models are passed through natively (tool use, images, thinking, prompt caching, real streaming).
* **OpenAI API:** text chat and embeddings for every model. Tool calling, images and `response_format` aren't supported, and `stream: true` returns the answer only once it's complete. `max_tokens` defaults to 1024.
* **End users:** OpenAI's `user` and Anthropic's `metadata.user_id` are recorded (up to 255 characters) so Reports can filter by end user. Claude Code's per-session IDs are ignored.
* **Errors:** `401` no key, `403` invalid key or model not allowed, `429` budget or token limit reached, `400`/`404` unknown model.
* Keep the key on a server, in an environment variable or secret store. Never ship it in a browser or mobile app.

---

## 🔔 Budgets, Usage Alerts & Daily Summaries

Each API key can have a monthly budget (USD) and a monthly token limit. Admins set these per key (Dashboard → API Keys → Edit):

* **Owners:** users who can sign in and see the key's usage.
* **Owner emails:** extra addresses that get the key's alerts. They don't need a login.
* **Usage alerts on/off:** also available as a switch on each key card.
* **Alert thresholds:** for example `50, 80, 100`. If left empty, the key uses `USAGE_ALERT_THRESHOLDS` (default `80,90,100`).

Each threshold is emailed once per key per month to the owners and owner emails. **Send test alert** checks delivery. Users with *Daily usage summary* turned on (Users tab) get yesterday's usage each day at `DAILY_SUMMARY_HOUR_UTC`.

Emails need an SMTP server (`SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM`). Any provider works, for example Amazon SES, SendGrid or Microsoft 365 SMTP. The **Notifications** tab shows SMTP status and can send a test email.

Set `ENFORCE_MONTHLY_BUDGETS=true` to reject requests (HTTP 429) once a key reaches 100% of its budget or token limit. By default the gateway only sends alerts.

---

## 📊 Usage Reports

Admins can build custom cost and token reports under **Reports**:

* **Filters** (each accepts several values): date range (UTC, with presets), teams, applications, API keys, owners (including "no owner"), models, providers, client APIs and end users.
* **Group by** any combination of date, week, month, team, application, API key, owner, model, provider, client API and end user, in the order you pick them. Choose no grouping to list individual requests.
* **Columns:** requests, input, output and total tokens, cache read and cache write tokens, and cost.
* **Export** to **Excel (.xlsx)** or **CSV**. The Excel file includes a totals row and a second sheet listing the filters used. Exports hold up to 200,000 rows; the page shows the first 5,000.

Owners are an API key's current owners. When grouping by owner, a key with several owners appears under each of them, but the totals count its usage once.

---

## ⚙️ Environment Variables Reference

See `.env.example` for the full list.

| Variable Name | Description | Default | Required |
| :--- | :--- | :--- | :--- |
| `ENVIRONMENT` | Deployment mode (`dev`, `production`) | `dev` | Yes |
| `GATEWAY_NAME` | Identifier for the gateway instance | `sprout-ai-gateway` | Yes |
| `MYSQL_HOST` | Database host (set to `db` automatically by docker compose) | `localhost` | Yes |
| `MYSQL_PORT` | Database port | `3306` | Yes |
| `MYSQL_DATABASE` | Database name | `sproutai_db` | Yes |
| `MYSQL_USER` | Database username | `sproutai_user` | Yes |
| `MYSQL_PASSWORD` | Database user password | *None* | Yes |
| `API_KEY_HASH_PEPPER` | Secret for hashing gateway API keys. Don't change it after keys are issued. | *None* | Yes |
| `ADMIN_EMAIL` | Email of the first admin, created on first start | *None* | Yes (first start) |
| `ADMIN_PASSWORD` | Password of the first admin (at least 10 characters) | *None* | Yes (first start) |
| `SESSION_TTL_HOURS` | How long a sign-in lasts | `12` | No |
| `SESSION_COOKIE_SECURE` | `auto`, `true` or `false`. `auto` sets the Secure flag on the session cookie over HTTPS. | `auto` | No |
| `MAX_FAILED_LOGINS` / `LOGIN_LOCKOUT_MINUTES` | Account lockout policy | `5` / `15` | No |
| `CORS_ORIGINS` | Only needed if the UI is hosted on a different origin | *None* | No |
| `AWS_REGION` | AWS Region for Bedrock calls | `us-east-2` | No |
| `AWS_BEARER_TOKEN_BEDROCK` | AWS Bedrock authentication token | *None* | No |
| `OPENAI_API_KEY` | OpenAI API Secret Key | *None* | No |
| `ANTHROPIC_API_KEY` | Anthropic API Secret Key | *None* | No |
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI Resource Endpoint | *None* | No |
| `AZURE_OPENAI_API_KEY` | Azure OpenAI Key | *None* | No |
| `ENFORCE_MONTHLY_BUDGETS` | Block requests at 100% of a key's budget or token limit | `false` | No |
| `USAGE_ALERT_THRESHOLDS` | Default alert thresholds (%), which can be overridden per key | `80,90,100` | No |
| `DAILY_SUMMARY_HOUR_UTC` | Hour (UTC) daily summaries are sent | `8` | No |
| `PUBLIC_BASE_URL` | Gateway URL used for links in emails | *None* | No |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM` | SMTP server for alert emails | *None*, `587` | For emails |
| `SMTP_USE_TLS` / `SMTP_USE_SSL` | STARTTLS (port 587) or implicit TLS (port 465) | `true` / `false` | No |

Docker Compose-only settings (set in `.env` or your shell): `GATEWAY_PORT` (host port, default `8000`) and `GATEWAY_VERSION` (image tag, default `latest`).

---

## 🔄 Upgrading

```bash
docker compose pull
docker compose up -d
```

Database changes are applied automatically when the gateway starts, and your data in the `sproutai_mysql_data` volume is kept. When upgrading from a version without built-in login, add `ADMIN_EMAIL` and `ADMIN_PASSWORD` to your `.env` before restarting. That version's UI API key settings (`VITE_GATEWAY_API_KEY`, `GATEWAY_UI_API_KEY`) are no longer used and can be removed. `API_KEYS_JSON` is also no longer used: keys it created earlier are already stored in the database and keep working, and new keys are created in the web UI (API Keys). You can delete it from `.env`.

To pin a version instead of `latest`, set `GATEWAY_VERSION` (for example `GATEWAY_VERSION=v1.2.0`).

### Upgrading the database from MySQL 8.0 to 8.4

The bundled database now uses **MySQL 8.4 LTS**, because MySQL 8.0 reached end of life in April 2026. On first start, MySQL 8.4 upgrades the existing data in the `sproutai_mysql_data` volume automatically. Back it up before you pull:

```bash
docker exec sproutai-mysql sh -c 'mysqldump --no-tablespaces -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' > sproutai-backup.sql
docker compose pull
docker compose up -d
```

The upgrade can't be undone in place. To go back to 8.0, restore the backup into a fresh 8.0 volume.

If you use your own MySQL server (for example Amazon RDS or Azure Database for MySQL), the gateway supports 8.0 and 8.4.

---

## 🔒 Production Checklist

* Serve the gateway over **HTTPS**, for example behind a load balancer or reverse proxy that sends `X-Forwarded-Proto`. Sign-in cookies are then marked Secure automatically.
* Use long random values for `API_KEY_HASH_PEPPER`, `MYSQL_PASSWORD` and `ADMIN_PASSWORD`, and keep them in a secrets manager.
* Set `PUBLIC_BASE_URL` so links in emails point to your gateway.
* Running several gateway replicas is supported. Sessions live in MySQL, and a database lock ensures alert emails are only sent once.

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
  "API_KEY_HASH_PEPPER": "your-random-hash-pepper",
  "ADMIN_PASSWORD": "initial-admin-password",
  "SMTP_PASSWORD": "your-smtp-password"
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
      "image": "ghcr.io/sproutlogix/ai_gateway_core:latest",
      "essential": true,
      "portMappings": [{ "containerPort": 8000, "hostPort": 8000 }],
      "environment": [
        { "name": "ENVIRONMENT", "value": "production" },
        { "name": "GATEWAY_NAME", "value": "sproutai-prod" },
        { "name": "MYSQL_HOST", "value": "sproutai-rds.cluster-123456789012.us-east-2.rds.amazonaws.com" },
        { "name": "MYSQL_PORT", "value": "3306" },
        { "name": "MYSQL_DATABASE", "value": "sproutai_db" },
        { "name": "MYSQL_USER", "value": "sproutai_user" },
        { "name": "ADMIN_EMAIL", "value": "admin@yourcompany.com" },
        { "name": "PUBLIC_BASE_URL", "value": "https://ai-gateway.yourcompany.com" },
        { "name": "SMTP_HOST", "value": "email-smtp.us-east-2.amazonaws.com" },
        { "name": "SMTP_PORT", "value": "587" },
        { "name": "SMTP_USERNAME", "value": "your-smtp-username" },
        { "name": "SMTP_FROM", "value": "ai-gateway@yourcompany.com" }
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
        },
        {
          "name": "ADMIN_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:us-east-2:123456789012:secret:sproutai/production/secrets:ADMIN_PASSWORD::"
        },
        {
          "name": "SMTP_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:us-east-2:123456789012:secret:sproutai/production/secrets:SMTP_PASSWORD::"
        }
      ]
    }
  ]
}
```

Point the load balancer's health check at `/health`.

---

### Option B: Azure App Service Deployment

Azure App Service allows referencing **Azure Key Vault** secrets directly in application environment settings.

#### 1. Store Secrets in Azure Key Vault
Store these secret values in Azure Key Vault: `MYSQL-PASSWORD`, `OPENAI-API-KEY`, `ANTHROPIC-API-KEY`, `API-KEY-HASH-PEPPER`, `ADMIN-PASSWORD` and `SMTP-PASSWORD`.

#### 2. Enable Managed Identity
1. Navigate to your App Service -> **Settings > Identity** and enable **System-assigned Managed Identity**.
2. Assign the **Key Vault Secrets User** role to this identity inside your Azure Key Vault.

#### 3. Map App Settings to Key Vault
In Azure Portal, navigate to App Service -> **Settings > Environment variables > App settings**, and add:

| Setting Name | Configuration Value |
| :--- | :--- |
| `ENVIRONMENT` | `production` |
| `WEBSITES_PORT` | `8000` |
| `MYSQL_HOST` | `sproutai-db.mysql.database.azure.com` |
| `MYSQL_DATABASE` | `sproutai_db` |
| `MYSQL_USER` | `sproutai_user` |
| `MYSQL_PASSWORD` | `@Microsoft.KeyVault(VaultName=my-keyvault;SecretName=MYSQL-PASSWORD)` |
| `OPENAI_API_KEY` | `@Microsoft.KeyVault(VaultName=my-keyvault;SecretName=OPENAI-API-KEY)` |
| `ANTHROPIC_API_KEY` | `@Microsoft.KeyVault(VaultName=my-keyvault;SecretName=ANTHROPIC-API-KEY)` |
| `API_KEY_HASH_PEPPER` | `@Microsoft.KeyVault(VaultName=my-keyvault;SecretName=API-KEY-HASH-PEPPER)` |
| `ADMIN_EMAIL` | `admin@yourcompany.com` |
| `ADMIN_PASSWORD` | `@Microsoft.KeyVault(VaultName=my-keyvault;SecretName=ADMIN-PASSWORD)` |
| `PUBLIC_BASE_URL` | `https://<your-app>.azurewebsites.net` |
| `SMTP_HOST` / `SMTP_USERNAME` / `SMTP_FROM` | Your SMTP server details |
| `SMTP_PASSWORD` | `@Microsoft.KeyVault(VaultName=my-keyvault;SecretName=SMTP-PASSWORD)` |

---

## 💼 Sproutlogix Enterprise Consultancy & Services

The Sprout AI Gateway container is **100% free for commercial use**. For enterprise organizations requiring tailored integration, Sproutlogix offers professional advisory and engineering services:

* **Azure Purview Governance:** Automated prompt data lineage, audit logging, and custom sensitivity cataloging.
* **Custom Gateway Plugins:** Proprietary middleware development, token rate limiting rules, and internal SSO/OAuth2 integrations.
* **Private RAG & Fine-Tuning:** In-house vector database deployment, pipeline construction, and enterprise security reviews.

📧 **Get in touch:** [https://sproutlogix.com/contact-us](https://sproutlogix.com/contact-us)

The same contact details are in the web UI under **Help → Contact Sproutlogix**. Report bugs on [GitHub Issues](https://github.com/Sproutlogix/sproutai-gateway/issues).

---

## 📜 License

Sprout AI Gateway Community Edition is distributed under the **Apache 2.0 License**.
