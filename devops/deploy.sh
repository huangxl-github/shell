#!/bin/bash
# Script Name: deploy.sh
# 
# Description: Production-ready deployment script with rollback capability
# Author: huangxl-github / Adapted from CI/CD best practices and deployment patterns
# Usage: ./deploy.sh [environment] [options|--help]
#
# Features:
#   • Multi-environment support (dev, staging, production)
#   • Git version control integration
#   • Automatic backup before deployment
#   • Health check verification
#   • One-command rollback
#   • Detailed logging and notifications

set -euo pipefail

# ===========================
# Configuration & Constants
# ===========================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Timestamps for logging
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:=$HOME/project}"  # Modify this to your project path
DEPLOY_DIR="${DEPLOY_DIR:-$PROJECT_ROOT/deploy}"
BACKUP_DIR="${BACKUP_DIR:=$PROJECT_ROOT/backup}"

# Application settings (modify for your app)
APP_NAME="${APP_NAME:-my-application}"
APP_USER="${APP_USER:-www-data}"  # User running the application
LOG_MAX_SIZE="10M"                # Max size per log file

# Environment-specific configurations
declare -A ENV_CONFIG=(
    ["dev"]="development.example.com:8080"
    ["staging"]="staging.example.com:443"
    ["production"]="example.com:443"
)

# ===========================
# Utility Functions
# ===========================

log_info() { echo -e "${BLUE}[INFO $(date +"%H:%M:%S")]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS ${date +"%H:%M:%S"}]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING ${date +"%H:%M:%S"}]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR ${date +"%H:%M:%S"}]${NC} $1" >&2; }
log_header() { echo -e "\n${CYAN}══════════════════════════$1══════════════════════════${NC}\n"; }

# Create log directory and initialize logging
setup_logging() {
    mkdir -p "${DEPLOY_DIR}/logs"
    
    LOG_FILE="${DEPLOY_DIR}/logs/deploy_${TIMESTAMP}.log"
    BACKUP_LOG="${DEPLOY_DIR}/logs/deploy_${TIMESTAMP}_backup.log"
    
    # Redirect all output to log file
    exec > >(tee -a "$LOG_FILE") 2>&1
    
    log_info "Log file: $LOG_FILE"
}

# Check required dependencies
check_dependencies() {
    local deps=("git" "tar" "find")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "Required dependency not found: $dep"
            exit 1
        fi
    done
    
    # Check if running as root (for production)
    if [ "$ENVIRONMENT" = "production" ] && [ "$EUID" -ne 0 ]; then
        log_warning "Production deployment usually requires root privileges"
    fi
    
    log_success "All dependencies satisfied"
}

# Create application backup
backup_application() {
    local BACKUP_PATH="${BACKUP_DIR}/${APP_NAME}_${TIMESTAMP}"
    
    if [ ! -d "$DEPLOY_DIR/$APP_NAME" ]; then
        log_warning "No existing deployment found. Skipping backup."
        return 0
    fi
    
    log_header "Creating Backup"
    
    mkdir -p "$BACKUP_DIR"
    
    # Stop application service (if systemd is available)
    if systemctl list-units --type=service | grep -q "$APP_NAME"; then
        log_info "Stopping $APP_NAME service..."
        sudo systemctl stop "$APP_NAME" 2>/dev/null || log_warning "Could not stop service"
    fi
    
    # Create backup archive
    log_info "Creating backup archive..."
    tar -czf "${BACKUP_PATH}.tar.gz" \
        --exclude="logs" \
        --exclude="*.log" \
        --exclude="node_modules" \
        --exclude=".git" \
        -C "$(dirname $DEPLOY_DIR/$APP_NAME)" \
        "$(basename $DEPLOY_DIR/$APP_NAME)" 2>/dev/null
    
    # Verify backup integrity
    if tar -tzf "${BACKUP_PATH}.tar.gz" > /dev/null 2>&1; then
        BACKUP_SIZE=$(du -h "${BACKUP_PATH}.tar.gz" | cut -f1)
        log_success "Backup created: ${BACKUP_PATH}.tar.gz (size: $BACKUP_SIZE)"
        echo "${BACKUP_PATH}.tar.gz" > "${DEPLOY_DIR}/current_backup.txt"
    else
        log_error "Backup verification failed!"
        exit 1
    fi
    
    # Clean up old backups (keep last 3)
    cd "$BACKUP_DIR" && find . -name "${APP_NAME}_*.tar.gz" | sort | head -n -3 | xargs rm -f 2>/dev/null || true
    
    BACKUP_PATH="${BACKUP_PATH}.tar.gz"
}

# Deploy application code
deploy_code() {
    log_header "Deploying Application Code"
    
    local TARGET_DIR="${DEPLOY_DIR}/${APP_NAME}_${TIMESTAMP}"
    
    # Create target directory
    mkdir -p "$TARGET_DIR"
    
    if [ "${GITHUB_REPO:-}" ]; then
        # Deploy from GitHub repository
        log_info "Cloning from GitHub: $GITHUB_REPO"
        
        git clone --branch "${GIT_BRANCH:-main}" --depth 1 "$GITHUB_REPO" "$TARGET_DIR" || {
            log_error "Clone failed!"
            exit 1
        }
    elif [ -d "$DEPLOY_DIR/$APP_NAME/.git" ]; then
        # Pull latest changes from existing deployment
        log_info "Pulling updates to $TARGET_DIR..."
        
        cp -r "${DEPLOY_DIR}/${APP_NAME}"/* "$TARGET_DIR/" 2>/dev/null || true
        
        cd "$TARGET_DIR"
        git pull origin "${GIT_BRANCH:-main}" --depth 1 || {
            log_error "Git pull failed!"
            exit 1
        }
    else
        # Deploy from local directory (use PROJECT_ROOT)
        if [ -d "$PROJECT_ROOT/build" ] || [ -d "$PROJECT_ROOT/dist" ]; then
            SOURCE_DIR="$([ -d "$PROJECT_ROOT/dist" ] && echo "dist" || echo "build")"
            log_info "Copying build artifacts from $SOURCE_DIR..."
            
            cp -r "${PROJECT_ROOT}/${SOURCE_DIR}"/* "$TARGET_DIR/" 2>/dev/null || true
        else
            log_error "No source code found! Check GITHUB_REPO or PROJECT_ROOT configuration."
            exit 1
        fi
    fi
    
    # Install dependencies if package.json exists (Node.js)
    if [ -f "$TARGET_DIR/package.json" ]; then
        cd "$TARGET_DIR" && npm install --production --omit=dev || {
            log_error "NPM install failed!"
            exit 1
        }
        log_success "Dependencies installed"
    fi
    
    # Install Python dependencies
    if [ -f "$TARGET_DIR/requirements.txt" ]; then
        cd "$TARGET_DIR" && pip install -r requirements.txt --target="${TARGET_DIR}/.deps" || {
            log_error "PIP install failed!"
            exit 1
        }
    fi
    
    # Build application (JavaScript/Web projects)
    if [ -f "$TARGET_DIR/package.json" ] && grep -q '"build"' "$TARGET_DIR/package.json"; then
        cd "$TARGET_DIR" && npm run build || {
            log_warning "Build failed or not configured"
        }
    fi
    
    # Set proper permissions
    chmod -R 755 "$TARGET_DIR"
    
    log_success "Code deployed to $TARGET_DIR"
}

# Execute post-deployment scripts
post_deployment() {
    log_header "Post-Deployment"
    
    TARGET_DIR="${DEPLOY_DIR}/${APP_NAME}_${TIMESTAMP}"
    
    # Run database migrations (if present)
    if [ -f "$TARGET_DIR/migrate.sh" ] || [ -d "$TARGET_DIR/migrations" ]; then
        log_info "Running database migrations..."
        cd "$TARGET_DIR" && bash migrate.sh 2>/dev/null || log_warning "Migration script not found or failed"
    fi
    
    # Run post-deployment hooks
    if [ -f "$TARGET_DIR/scripts/post-deploy.sh" ]; then
        log_info "Executing post-deploy hook..."
        cd "$TARGET_DIR" && bash scripts/post-deploy.sh || {
            log_warning "Post-deploy script had issues"
        }
    fi
    
    log_success "Post-deployment completed"
}

# Verify deployment health
health_check() {
    log_header "Health Check"
    
    # Application endpoint check (modify based on your app)
    local ENDPOINT="${HEALTH_ENDPOINT:-http://localhost:$PORT/api/health}"
    local MAX_RETRIES=10
    local RETRIES=0
    
    log_info "Checking application health at: $ENDPOINT"
    
    while [ $RETRIES -lt $MAX_RETRIES ]; do
        if curl -s "$ENDPOINT" | grep -q '"status": *"healthy"' 2>/dev/null; then
            log_success "Health check passed!"
            return 0
        fi
        
        RETRIES=$((RETRIES + 1))
        
        if [ $RETRIES -eq $MAX_RETRIES ]; then
            log_error "Health check failed after $MAX_RETRIES attempts"
            return 1
        fi
        
        sleep 2
    done
    
    return 1
}

# Switch symlink to new deployment (zero-downtime deployment)
switch_deployment() {
    local TARGET_DIR="${DEPLOY_DIR}/${APP_NAME}_${TIMESTAMP}"
    local CURRENT_LINK="${DEPLOY_DIR}/${APP_NAME}"
    
    log_header "Switching Deployment"
    
    # Create symlink if it doesn't exist
    if [ ! -L "$CURRENT_LINK" ]; then
        mv "$TARGET_DIR" "${DEPLOY_DIR}/${APP_NAME}"
    else
        # Swap symlinks for zero-downtime deployment
        cd "$DEPLOY_DIR" && ln -sfn "${APP_NAME}_${TIMESTAMP}" "${APP_NAME}" || {
            log_error "Failed to switch deployment!"
            exit 1
        }
        
        rm -rf "${DEPLOY_DIR}/${APP_NAME}_$(date -d "1 hour ago" +"%Y%m%d_%H%M%S" | head -c20)"
        
        log_success "Zero-downtime switch completed"
    fi
    
    # Restart service if systemd unit exists
    if systemctl list-units --type=service | grep -q "$APP_NAME"; then
        log_info "Restarting ${APP_NAME} service..."
        sudo systemctl restart "$APP_NAME" || {
            log_error "Service restart failed!"
            exit 1
        }
    fi
    
    log_success "Deployment switch completed!"
}

# Rollback to previous deployment
rollback() {
    local TARGET_BACKUP="${BACKUP:-}"
    
    if [ -z "$TARGET_BACKUP" ]; then
        # Get most recent backup
        TARGET_BACKUP=$(cat "${DEPLOY_DIR}/current_backup.txt") 2>/dev/null || {
            log_error "No backup found!"
            exit 1
        }
        
        log_warning "Using automatic latest backup: $TARGET_BACKUP"
        read -p "Confirm rollback? (y/N): " -n 1 -r
        echo ""
        
        [[ ! $REPLY =~ ^[Yy]$ ]] && { log_warning "Rollback cancelled"; exit 0; }
    fi
    
    if [ ! -f "$TARGET_BACKUP" ]; then
        log_error "Backup file not found: $TARGET_BACKUP"
        exit 1
    fi
    
    log_header "Rolling Back to: $(basename "$TARGET_BACKUP")"
    
    # Stop application
    sudo systemctl stop "$APP_NAME" 2>/dev/null || true
    
    # Remove current deployment
    rm -rf "${DEPLOY_DIR}/${APP_NAME}"
    
    # Extract backup
    tar -xzf "$TARGET_BACKUP" -C "$DEPLOY_DIR"
    
    # Verify rollback
    if [ -d "${DEPLOY_DIR}/${APP_NAME}" ]; then
        # Restart application
        sudo systemctl start "$APP_NAME" 2>/dev/null || {
            log_warning "Service not configured to auto-start after rollback"
        }
        
        log_success "Rollback completed successfully!"
    else
        log_error "Rollback failed! Application directory not found."
        exit 1
    fi
}

# Generate deployment report
generate_report() {
    local DEPLOY_STATUS="${1:-success}"
    
    cat << EOF | tee -a "${LOG_FILE}"

=============================================================================================
                        DEPLOYMENT REPORT
============================================================================================
Time:         ${TIMESTAMP}
Environement: ${ENVIRONMENT}
Application:  ${APP_NAME}
Status:       ${DEPLOY_STATUS}

Deployment Directory: ${DEPLOY_DIR}/${APP_NAME}
Backup Location:      ${BACKUP_PATH:-N/A}
Logs:                 ${LOG_FILE}

=============================================================================================
EOF

    # Send notification (optional - modify for Slack/Teams/Discord)
    if [ "${SEND_NOTIFICATIONS:-}" = "true" ] && command -v curl &> /dev/null; then
        WEBSITE="${WEBHOOK_URL}"  # Add your webhook URL
        
        curl -X POST "$WEBHOOK_URL" \
            -H 'Content-type: application/json' \
            -d "{
                \"text\": \"Deployment ${APP_NAME} (${ENVIRONMENT}): ${DEPLOY_STATUS}\",
                \"username\": \"Deploy Bot\",
                \"icon_emoji\":\":rocket:\"
            }" 2>/dev/null || true
    fi
}

# Main deployment flow
deploy() {
    ENVIRONMENT="${1:-dev}"
    
    log_header "Starting Deployment | Environment: ${ENVIRONMENT}"
    
    local EXIT_CODE=0
    
    # Pre-deployment checks
    check_dependencies
    setup_logging
    
    # Backup current deployment (if exists)
    backup_application
    
    # Deploy new code
    deploy_code || EXIT_CODE=1
    
    if [ $EXIT_CODE -eq 0 ]; then
        post_deployment
        
        # Switch to new deployment
        switch_deployment
        
        # Health check
        health_check || { log_warning "Health check failed!"; EXIT_CODE=1 }
        
        if [ $EXIT_CODE -eq 0 ]; then
            generate_report "success"
            log_success "Deployment successful! 🎉"
        else
            log_error "Deployment had issues!"
        fi
    else
        log_error "Deployment failed! Consider rolling back."
        rollback --target-backup="${BACKUP_PATH:-auto}" || true
        generate_report "failed"
        exit 1
    fi
}

# Show usage and help
show_usage() {
    cat << EOF

${BLUE}=== Production Deployment Script ==${NC}

Usage: $0 <command> [options]

Commands:
  deploy [env]       Deploy application (dev/staging/production)
  rollback [--backup=FILE]   Rollback to previous deployment
  help               Show this help message

Environment Variables:
  PROJECT_ROOT       Your project root directory (default: ~/project)
  APP_NAME           Application name (default: my-application)
  GITHUB_REPO        GitHub repository URL (for external deployment)
  GIT_BRANCH         Git branch to deploy (default: main)
  PORT               Application port
  HEALTH_ENDPOINT    Health check URL

Examples:
  $0 deploy dev              # Deploy to development environment
  $0 deploy production       # Deploy to production
  $0 rollback                # Use latest backup for rollback
  $0 rollback --backup=/path/to/backup.tar.gz  # Rollback to specific backup

Configuration:
  Modify SCRIPT settings at the top of this file.
  Read more: https://github.com/huangxl-github/shell/tree/main/devops

EOF
}

# ===========================
# Main Execution
# ===========================

case "${1:-help}" in
    deploy)
        shift
        deploy "$@"
        ;;
    rollback)
        if [[ "${2:---backup=}" =~ --backup=(.+)$ ]]; then
            BACKUP="${BASH_REMATCH[1]}"
        fi
        rollback
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        log_error "Unknown command: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac
