#!/usr/bin/env bash

# ==============================================================================
# Sprout AI Gateway - Environment Installer
# ==============================================================================
# Description: Sets up the database the gateway uses, generates secure
#              credentials, creates the first admin login, and updates .env.
#
# The database can be:
#   docker    - a MySQL container started by docker compose (default)
#   host      - MySQL Server installed on this machine (Ubuntu/Debian, needs sudo)
#   existing  - a MySQL server you already run (Amazon RDS, Azure, another host, ...)
#
# Usage: ./install.sh                  # asks which one to use
#        ./install.sh --mysql docker   # or host / existing, without asking
#        ./install.sh --upgrade        # after `git pull`: adds new settings from
#                                      # .env.example to an existing .env, nothing else
# ==============================================================================

set -euo pipefail

# --- Color Formatting ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

usage() {
    echo "Usage: $0 [--mysql docker|host|existing] | --upgrade"
    echo "  --mysql docker    run MySQL as a container in docker compose (default)"
    echo "  --mysql host      install MySQL Server on this machine (Ubuntu/Debian, run with sudo)"
    echo "  --mysql existing  connect to a MySQL server you already run"
    echo "  --upgrade         only add settings that are new in .env.example to your .env"
}

# --- Arguments ---
MYSQL_MODE=""
UPGRADE_ONLY=false
while [ $# -gt 0 ]; do
    case "$1" in
        --mysql)
            [ $# -ge 2 ] || { usage; log_error "--mysql needs a value"; }
            MYSQL_MODE="$2"; shift 2 ;;
        --mysql=*) MYSQL_MODE="${1#*=}"; shift ;;
        --upgrade) UPGRADE_ONLY=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; log_error "Unknown option: $1" ;;
    esac
done
case "$MYSQL_MODE" in
    ""|docker|host|existing) ;;
    *) usage; log_error "--mysql must be docker, host or existing" ;;
esac
if [ "$UPGRADE_ONLY" = true ] && [ -n "$MYSQL_MODE" ]; then
    usage; log_error "--upgrade can't be combined with --mysql"
fi

# --- Prompt Helpers (read from the terminal, so `curl ... | bash` still works) ---
HAS_TTY=false
if { : < /dev/tty; } 2>/dev/null; then
    HAS_TTY=true
fi

# ask "Question" "default" -> prints the answer (the default when left empty)
ask() {
    local answer=""
    read -r -p "$1 [$2]: " answer < /dev/tty
    echo "${answer:-$2}"
}

ask_secret() {
    local answer=""
    read -r -s -p "$1: " answer < /dev/tty
    echo "" > /dev/tty
    echo "$answer"
}

# --- File Paths ---
ENV_FILE=".env"
ENV_EXAMPLE=".env.example"

[ -f "$ENV_EXAMPLE" ] || log_error "$ENV_EXAMPLE was not found. Run this script from the repository folder."

# Ensure .env exists or create it from .env.example
ENV_EXISTED=true
if [ ! -f "$ENV_FILE" ]; then
    ENV_EXISTED=false
    [ "$UPGRADE_ONLY" = false ] || log_error "There is no .env to upgrade. Run ./install.sh first."
    if [ -f "$ENV_EXAMPLE" ]; then
        log_info "Creating .env from .env.example..."
        cp "$ENV_EXAMPLE" "$ENV_FILE"
    else
        log_error "Neither .env nor .env.example was found in this directory."
    fi
fi

# --- Helper Function: Generate Random Strings ---
generate_random_string() {
    local length=${1:-24}
    # cut reads all of its input, so nothing in the pipeline is killed by SIGPIPE (set -o pipefail).
    head -c 2048 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c "1-${length}"
}

# --- Helper Functions: Read / Set / Remove a key in .env ---
get_env_var() {
    { grep -E "^${1}=" "$ENV_FILE" || true; } | tail -n 1 | cut -d= -f2-
}

# A value that still has to be filled in: empty or a <placeholder> from .env.example
is_unset() {
    [ -z "$1" ] || [[ "$1" == \<* ]]
}

set_env_var() {
    local key="$1"
    local value="$2"

    # Escape special characters for sed
    local escaped_value
    escaped_value=$(printf '%s\n' "$value" | sed -e 's/[\/&]/\\&/g')

    if grep -q "^${key}=" "$ENV_FILE"; then
        # -i.bak works with both GNU sed (Linux) and BSD sed (macOS)
        sed -i.bak "s/^${key}=.*/${key}=${escaped_value}/" "$ENV_FILE"
        rm -f "${ENV_FILE}.bak"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

unset_env_var() {
    if grep -q "^${1}=" "$ENV_FILE"; then
        sed -i.bak "/^${1}=/d" "$ENV_FILE"
        rm -f "${ENV_FILE}.bak"
    fi
}

# Keeps a value that is already set: the database and issued API keys depend on it.
keep_or_generate() {
    local current
    current=$(get_env_var "$1")
    if is_unset "$current"; then
        generate_random_string "$2"
    else
        echo "$current"
    fi
}

# --- Helper Function: Add Settings That Are New in .env.example ---
# Appends every setting from .env.example that .env doesn't mention yet, with the comment
# lines above it. Values in .env are never changed. Placeholders such as <your-api-key> are
# added commented out: a placeholder would otherwise count as a configured value.
ADDED_VARS=()
NEEDS_VALUE_VARS=()
add_missing_env_vars() {
    local line key value comments="" added_block=false
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^[[:space:]]*$ ]]; then
            comments=""
            continue
        fi
        if [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            # Present, or deliberately commented out by the user (#KEY= or # KEY=)
            if grep -qE "^#? ?${key}=" "$ENV_FILE"; then
                comments=""
                continue
            fi
            if [ "$added_block" = false ]; then
                # Start on a new line even if .env doesn't end with one
                [ -z "$(tail -c 1 "$ENV_FILE")" ] || echo "" >> "$ENV_FILE"
                printf '\n# ==============================================================================\n' >> "$ENV_FILE"
                printf '# Added by install.sh on %s (new in .env.example)\n' "$(date -u +%Y-%m-%d)" >> "$ENV_FILE"
                printf '# ==============================================================================\n' >> "$ENV_FILE"
                added_block=true
            fi
            if [ -n "$comments" ]; then
                # A blank line between groups, as in .env.example
                [ ${#ADDED_VARS[@]} -eq 0 ] || echo "" >> "$ENV_FILE"
                printf '%s' "$comments" >> "$ENV_FILE"
            fi
            comments=""
            if is_unset "$value" && [ -n "$value" ]; then
                printf '# %s=%s\n' "$key" "$value" >> "$ENV_FILE"
                NEEDS_VALUE_VARS+=("$key")
            else
                printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
            fi
            ADDED_VARS+=("$key")
        elif [[ "$line" == \#* ]]; then
            comments+="$line"$'\n'
        fi
    done < "$ENV_EXAMPLE"
}

report_added_env_vars() {
    if [ ${#ADDED_VARS[@]} -eq 0 ]; then
        log_info "${ENV_FILE} already has every setting in ${ENV_EXAMPLE}."
        return
    fi
    log_info "Added ${#ADDED_VARS[@]} new setting(s) to the end of ${ENV_FILE}: ${ADDED_VARS[*]}"
    if [ ${#NEEDS_VALUE_VARS[@]} -gt 0 ]; then
        log_warn "Added commented out because they need your value (uncomment them if you use the feature): ${NEEDS_VALUE_VARS[*]}"
    fi
}

if [ "$ENV_EXISTED" = true ]; then
    log_info "Checking ${ENV_FILE} for settings that are new in ${ENV_EXAMPLE}..."
    add_missing_env_vars
    report_added_env_vars
fi

if [ "$UPGRADE_ONLY" = true ]; then
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Review the new settings at the end of .env:  nano .env"
    echo "2. Update and restart the gateway:  docker compose pull && docker compose up -d"
    echo ""
    exit 0
fi

# --- Step 1: Choose Where MySQL Runs ---
if [ -z "$MYSQL_MODE" ]; then
    if [ "$HAS_TTY" = true ]; then
        echo ""
        echo "The gateway stores its data in MySQL."
        answer=$(ask "Add a MySQL container to docker compose? (y/n)" "y")
        case "$answer" in
            [Yy]*) MYSQL_MODE="docker" ;;
            *)
                answer=$(ask "Install MySQL Server on this machine instead? (n = use a MySQL server you already run) (y/n)" "y")
                case "$answer" in
                    [Yy]*) MYSQL_MODE="host" ;;
                    *) MYSQL_MODE="existing" ;;
                esac
                ;;
        esac
    else
        MYSQL_MODE="docker"
        log_info "No terminal to ask on; using a MySQL container in docker compose (pass --mysql to choose)."
    fi
fi

# --- Step 2: Database Credentials ---
DB_NAME="sproutai_db"
DB_USER="sproutai_user"
DB_PORT="3306"
# Re-running the installer keeps the existing password: the MySQL data volume or user still has it.
DB_PASSWORD=$(keep_or_generate "MYSQL_PASSWORD" 32)

case "$MYSQL_MODE" in
    docker)
        DB_HOST="db"
        log_info "Using a MySQL container in docker compose (docker-compose.yml)."
        ;;

    host)
        DB_HOST="127.0.0.1"
        if [ "$EUID" -ne 0 ]; then
            log_error "Installing MySQL needs root. Run: sudo ./install.sh --mysql host"
        fi

        log_info "Checking MySQL installation..."
        if ! command -v mysql &> /dev/null; then
            command -v apt-get &> /dev/null \
                || log_error "Installing MySQL is only automated on Ubuntu/Debian. Install it yourself, then run: ./install.sh --mysql existing"
            log_info "MySQL not found. Installing mysql-server..."
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y
            apt-get install -y mysql-server
            systemctl enable mysql
            systemctl start mysql
        else
            log_info "MySQL is already installed."
        fi

        # Ensure MySQL service is running
        if ! systemctl is-active --quiet mysql; then
            log_info "Starting MySQL service..."
            systemctl start mysql
        fi

        log_info "Configuring MySQL database and privileges..."
        # ALTER USER keeps the password in step with .env when the user already existed.
        mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
EOF
        log_info "Database '${DB_NAME}' and user '${DB_USER}' configured successfully."
        ;;

    existing)
        [ "$HAS_TTY" = true ] \
            || log_error "--mysql existing asks for the server's details, so it needs a terminal. Or fill in the MYSQL_* settings in .env yourself."
        echo ""
        echo "Enter your MySQL server's details. The database and user must already exist,"
        echo "and the user needs all privileges on the database (the gateway creates its tables)."
        default_value=$(get_env_var "MYSQL_HOST")
        if is_unset "$default_value" || [ "$default_value" = "db" ]; then default_value="127.0.0.1"; fi
        DB_HOST=$(ask "MySQL host" "$default_value")
        default_value=$(get_env_var "MYSQL_PORT")
        DB_PORT=$(ask "MySQL port" "${default_value:-3306}")
        default_value=$(get_env_var "MYSQL_DATABASE")
        if is_unset "$default_value"; then default_value="$DB_NAME"; fi
        DB_NAME=$(ask "Database name" "$default_value")
        default_value=$(get_env_var "MYSQL_USER")
        if is_unset "$default_value"; then default_value="$DB_USER"; fi
        DB_USER=$(ask "Database user" "$default_value")
        DB_PASSWORD=$(ask_secret "Password for ${DB_USER}")
        [ -n "$DB_PASSWORD" ] || log_error "A database password is required."
        if [[ "$DB_PASSWORD" == *'$'* ]]; then
            log_warn "The password contains '\$', which docker compose treats as a variable in .env. Write it as \$\$ in .env."
        fi
        ;;
esac

# --- Step 3: Update the .env File ---
log_info "Updating ${ENV_FILE} with MySQL and Gateway settings..."

# Write Database settings
set_env_var "MYSQL_HOST" "$DB_HOST"
set_env_var "MYSQL_PORT" "$DB_PORT"
set_env_var "MYSQL_DATABASE" "$DB_NAME"
set_env_var "MYSQL_USER" "$DB_USER"
set_env_var "MYSQL_PASSWORD" "$DB_PASSWORD"

# docker compose reads COMPOSE_FILE from .env: without the bundled database it uses the gateway-only file.
if [ "$MYSQL_MODE" = "docker" ]; then
    unset_env_var "COMPOSE_FILE"
else
    set_env_var "COMPOSE_FILE" "docker-compose.external-db.yml"
fi

# Changing the pepper invalidates every issued API key, so an existing one is kept.
set_env_var "API_KEY_HASH_PEPPER" "$(keep_or_generate "API_KEY_HASH_PEPPER" 32)"

# First admin account for the web UI (only used when the gateway has no users yet).
# Keep an existing password unless it is still the placeholder.
CURRENT_ADMIN_PASSWORD=$(get_env_var "ADMIN_PASSWORD")
if is_unset "$CURRENT_ADMIN_PASSWORD"; then
    ADMIN_PASSWORD=$(generate_random_string 20)
    set_env_var "ADMIN_PASSWORD" "$ADMIN_PASSWORD"
else
    ADMIN_PASSWORD="(unchanged, see ADMIN_PASSWORD in .env)"
fi
ADMIN_EMAIL=$(get_env_var "ADMIN_EMAIL")
if [ -z "$ADMIN_EMAIL" ]; then
    ADMIN_EMAIL="admin@example.com"
    set_env_var "ADMIN_EMAIL" "$ADMIN_EMAIL"
fi

log_info ".env file successfully configured!"

# --- Step 4: Final Summary ---
case "$MYSQL_MODE" in
    docker) DB_SUMMARY="MySQL container in docker compose" ;;
    host) DB_SUMMARY="MySQL Server on this machine (${DB_HOST}:${DB_PORT})" ;;
    existing) DB_SUMMARY="your MySQL server (${DB_HOST}:${DB_PORT})" ;;
esac

echo ""
echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN}      Installation Complete!                                           ${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo ""
echo "Configured Settings in .env:"
echo "  - Database:             $DB_SUMMARY"
echo "  - MYSQL_DATABASE:       $DB_NAME"
echo "  - MYSQL_USER:           $DB_USER"
echo "  - ADMIN_EMAIL:          $ADMIN_EMAIL"
echo "  - ADMIN_PASSWORD:       $ADMIN_PASSWORD"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Open .env and add your provider API keys (OPENAI_API_KEY, ANTHROPIC_API_KEY, etc.)"
echo "   and, optionally, SMTP settings for usage alert emails:"
echo "   nano .env"
echo ""
echo "2. Start the gateway containers:"
echo "   docker compose up -d"
echo ""
echo "3. Open http://localhost:8000, sign in as $ADMIN_EMAIL and change the password."
echo ""
echo "4. Add model routes, then create gateway API keys under API Keys."
echo ""
