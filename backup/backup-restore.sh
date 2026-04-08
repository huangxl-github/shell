#!/bin/bash
# Script Name: daily-backup.sh
# Description: Automatically backup important directories and compress them with timestamps
# Author: huangxl-github / Adapted from awesome-shell-scripts collections
# Usage: ./backup-restore.sh [source_dir] [backup_dest]

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration - modify as needed
SOURCE_DIR="${1:-\"$HOME/Documents\"}"  # Source directory to backup
BACKUP_DEST="${2:-\"/tmp/backups\"}"    # Destination for backups
RETENTION_DAYS=${3:-7}                  # Number of days to keep backups
LOG_FILE="$BACKUP_DEST/backup_$(date +%F).log"

# Function to print colored messages
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if source directory exists
check_source() {
    if [ ! -d "$SOURCE_DIR" ]; then
        print_error "Source directory does not exist: $SOURCE_DIR"
        exit 1
    fi
}

# Create backup
do_backup() {
    print_info "Starting backup of: $SOURCE_DIR"
    print_info "Backup destination: $BACKUP_DEST"
    
    # Create backup destination if it doesn't exist
    mkdir -p "$BACKUP_DEST"
    
    # Generate timestamp for backup filename
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="backup_$(basename $SOURCE_DIR)_$TIMESTAMP.tar.gz"
    BACKUP_PATH="$BACKUP_DEST/$BACKUP_FILE"
    
    print_info "Creating backup: $BACKUP_FILE"
    
    # Create compressed backup with gzip, excluding common junk files
    tar -czf "$BACKUP_PATH" \
        --exclude='*.log' \
        --exclude='node_modules' \
        --exclude='.git' \
        --exclude='__pycache__' \
        -C "$(dirname $SOURCE_DIR)" \
        "$(basename $SOURCE_DIR)" 2>&1 | tee -a "$LOG_FILE"
    
    # Verify backup integrity
    if tar -tzf "$BACKUP_PATH" > /dev/null 2>&1; then
        print_success "Backup created successfully: $BACKUP_PATH"
        
        # Show backup size
        SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
        print_info "Backup size: $SIZE"
    else
        print_error "Backup verification failed!"
        exit 1
    fi
}

# Restore backup
do_restore() {
    if [ -z "${BACKUP_TO_RESTORE:-}" ]; then
        print_error "Please specify a backup file to restore"
        exit 1
    fi
    
    TARGET_DIR="${RESTORE_TARGET:=$HOME/restored_$(date +%Y%m%d_%H%M%S)}"
    
    print_info "Restoring backup: $BACKUP_TO_RESTORE"
    print_info "Restore target: $TARGET_DIR"
    
    tar -xzf "$BACKUP_TO_RESTORE" -C "$TARGET_DIR" 2>&1 | tee -a "$LOG_FILE"
    print_success "Restore completed to: $TARGET_DIR"
}

# Clean up old backups
cleanup_old_backups() {
    print_info "Cleaning up backups older than $RETENTION_DAYS days..."
    
    OLD_BACKUP_COUNT=$(find "$BACKUP_DEST" -name "backup_*.tar.gz" -type f -mtime +${RETENTION_DAYS} | wc -l)
    
    if [ "$OLD_BACKUP_COUNT" -gt 0 ]; then
        find "$BACKUP_DEST" -name "backup_*.tar.gz" -type f -mtime +${RETENTION_DAYS} -delete
        print_success "Cleaned up $OLD_BACKUP_COUNT old backup(s)"
    else
        print_info "No old backups to clean up"
    fi
}

# List existing backups
list_backups() {
    print_info "Existing backups in $BACKUP_DEST:"
    echo -e "\n${BLUE}Backup File                               Size       Date${NC}\n"
    
    ls -lah "$BACKUP_DEST"/backup_*.tar.gz 2>/dev/null | while read line; do
        echo "  $line"
    done
    
    BACKUP_COUNT=$(ls -1 "$BACKUP_DEST"/backup_*.tar.gz 2>/dev/null | wc -l)
    echo -e "\n${GREEN}Total backups: $BACKUP_COUNT${NC}\n"
}

# Main execution flow
log_header() {
    echo "=========================================" > "$LOG_FILE"
    echo "Backup Log: $(date)" >> "$LOG_FILE"
    echo "Source: $SOURCE_DIR" >> "$LOG_FILE"
    echo "Destination: $BACKUP_DEST" >> "$LOG_FILE"
    echo "=========================================" >> "$LOG_FILE"
}

case "${1:-backup}" in
    backup)
        check_source
        log_header
        do_backup
        cleanup_old_backups
        ;;
    restore)
        BACKUP_TO_RESTORE="$2"
        if [ -z "$BACKUP_TO_RESTORE" ]; then
            print_error "Usage: $0 restore <backup_file>"
            exit 1
        fi
        log_header
        do_restore
        ;;
    list)
        list_backups
        ;;
    *)
        echo "Usage: $0 {backup|restore|list} [options]"
        echo ""
        echo "Commands:"
        echo "  backup           Create a new backup (default)"
        echo "                   Usage: $0 backup <source_dir> <dest_path> [retention_days]"
        echo "  restore          Restore from backup"
        echo "                   Usage: $0 restore <backup_file>"
        echo "  list             List all backups"
        echo ""
        echo "Examples:"
        echo "  $0 ~Documents ~/backups 14   # Backup Documents with 14-day retention"
        echo "  $0 list                       # List all backups"
        echo "  $0 restore ~/backup_2024.tar.gz  # Restore specific backup"
        exit 0
        ;;
esac
