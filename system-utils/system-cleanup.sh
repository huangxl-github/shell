#!/bin/bash
# Script Name: system-cleanup.sh
# Description: Clean up system files, caches, and temporary files to free up disk space
# Author: huangxl-github / Adapted from various open-source cleanup scripts
# Usage: ./system-cleanup.sh [options]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default thresholds
DEFAULT_CACHE_SIZE_MB=500

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Display disk usage before cleanup
show_disk_usage() {
    echo ""
    print_info "=== Current Disk Usage ==="
    df -h | grep -E '^/dev/|Filesystem' | head -20
    echo ""
}

# Clean package manager caches
clean_package_cache() {
    print_info "Cleaning package manager caches..."
    
    # apt (Ubuntu/Debian)
    if command -v apt-get &> /dev/null; then
        print_info "  Cleaning apt cache..."
        SAVED_SIZE=$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1 || echo "0")
        sudo apt-get clean > /dev/null 2>&1
        CLEANED_SIZE=$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1 || echo "0")
        print_success "    Apt cache cleaned (was: $SAVED_SIZE, now: $CLEANED_SIZE)"
    fi
    
    # yum/dnf (RHEL/CentOS/Fedora)
    if command -v yum &> /dev/null; then
        print_info "  Cleaning yum cache..."
        sudo yum clean all > /dev/null 2>&1 || true
    fi
    
    if command -v dnf &> /dev/null; then
        print_info "  Cleaning dnf cache..."
        sudo dnf clean all > /dev/null 2>&1 || true
    fi
    
    # pip cache
    if command -v pip &> /dev/null; then
        print_info "  Cleaning pip cache..."
        pip cache purge > /dev/null 2>&1 || true
    fi
    
    # npm/yarn cache (Node.js)
    if command -v npm &> /dev/null; then
        print_info "  Cleaning npm cache..."
        npm cache clean --force > /dev/null 2>&1 || true
    fi
    
    if command -v yarn &> /dev/null; then
        print_info "  Cleaning yarn cache..."
        yarn cache clean > /dev/null 2>&1 || true
    fi
    
    # docker cache (if running)
    if command -v docker &> /dev/null; then
        print_info "  Cleaning Docker system..."
        docker system prune -af --volumes > /dev/null 2>&1 || true
        print_success "    Docker system pruned (use 'docker system df' to check)"
    fi
    
    print_success "Package manager caches cleaned!"
}

# Clean temporary files
clean_temp_files() {
    print_info "Cleaning temporary files..."
    
    TMP_DIRS=("/tmp" "/var/tmp" "$HOME/.cache")
    
    for dir in "${TMP_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            SIZE_BEFORE=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "0")
            
            # Remove old temporary files (older than 7 days)
            sudo find "$dir" -type f -mtime +7 -delete > /dev/null 2>&1 || true
            sudo find "$dir" -type d -empty -mtime +7 -delete > /dev/null 2>&1 || true
            
            SIZE_AFTER=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "0")
            print_success "    $dir cleaned (was: $SIZE_BEFORE, now: $SIZE_AFTER)"
        fi
    done
}

# Clean browser caches
clean_browser_cache() {
    print_info "NOTE: Browser cache cleaning disabled for safety."
    print_warning "Browsers maintain their own cleanup utilities. Use them directly!"
    
    # Optional: Add manual instructions if users want to do it themselves
    print_info "Manual browser cleanup:"
    echo -e "  • Chrome/Edge: Settings > Privacy > Clear browsing data"
    echo -e "  • Firefox: Settings > Privacy & Security > Cookies and Site Data"
    echo -e "  • Safari: Develop > Empty Caches (enable Develop menu) or use History menu\n"
}

# Clean log files
clean_log_files() {
    if ! sudo -v 2>/dev/null; then
        print_warning "Skip system log cleaning (requires sudo)"
        return
    fi
    
    print_info "Cleaning old log files..."
    
    # Clear rotated log files older than 14 days
    sudo find /var/log -name "*.gz" -type f -mtime +14 -delete > /dev/null 2>&1 || true
    sudo find /var/log -name "*.old" -type f -mtime +14 -delete > /dev/null 2>&1 || true
    
    # Truncate large log files (only if larger than 50MB and not the main system logs)
    sudo find /var/log -maxdepth 2 ! -name "syslog*" ! -name "messages" ! -name "journal*" `
             -type f -size +50M -exec truncate -s 1M {} \; > /dev/null 2>&1 || true
    
    print_success "Old log files cleaned!"
}

# Clean large files finder
find_large_files() {
    print_info "Finding large directories (over 1GB)..."
    
    echo ""
    echo -e "${CYAN}Top 10 Largest Directories:${NC}"
    du -ah /home 2>/dev/null | sort -rh | head -10 | while read line; do
        echo "  $line"
    done
    
    if [ "$HOME/.cache" ]; then
        CACHE_SIZE=$(du -sh "$HOME/.cache" 2>/dev/null | cut -f1 || echo "N/A")
        echo -e "\n${CYAN}User Cache Size: $CACHE_SIZE${NC}"
    fi
}

# Clean development files
clean_dev_files() {
    print_info "Cleaning development artifacts..."
    
    # Check if running in a git repository
    if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        print_info "Inside git repository, cleaning untracked files..."
        
        # Show count first (dry-run)
        UNTRACKED_COUNT=$(git ls-files --others --exclude-standard | wc -l)
        print_warning "Found $UNTRACKED_COUNT untracked files"
        print_info "To clean them, you can run: git clean -fdx"
    fi
    
    # Clean node_modules if exists (warning!)
    if [ -d "$PWD/node_modules" ]; then
        NODE_SIZE=$(du -sh "$PWD/node_modules" 2>/dev/null | cut -f1 || echo "N/A")
        print_warning "node_modules detected (size: $NODE_SIZE)")
        print_info "Use 'rm -rf node_modules' to remove if needed"
    fi
    
    # Clean build artifacts
    BUILD_ARTIFACTS=("build/" "dist/" "target/" ".next/" "out/")
    for artifact in "${BUILD_ARTIFACTS[@]}"; do
        if [ -d "$PWD/$artifact" ]; then
            print_warning "Build directory found: $artifact"
            print_info "Consider removing with: rm -rf $artifact"
        fi
    done
    
    print_success "Development artifacts check completed!"
}

# Show usage statistics before and after
show_cleanup_summary() {
    echo ""
    print_info "=== Cleanup Summary ==="
    
    # Disk space used
    echo -e "${CYAN}Disk Usage:${NC}"
    df -h | tail -n +2 | grep -E '^/dev/' || true
    
    echo ""
    print_success "Cleanup completed! 🎉"
    print_info "For persistent improvements, consider:"
    echo "  • Regular apt/yum cache cleaning (cron job)"
    echo "  • Docker image cleanup for containers you're not using"
    echo "  • Reviewing large directories periodically\n"
}

# Main execution flow
main() {
    print_info "System Cleanup Utility"
    print_info "======================"
    echo ""
    
    # Show current disk usage
    show_disk_usage
    
    # Perform cleanup actions
    CLEAN_TYPE="${1:-all}"
    
    case "$CLEAN_TYPE" in
        package)
            clean_package_cache
            ;;
        temp)
            clean_temp_files
            ;;
        logs)
            sudo -v > /dev/null 2>&1 || { print_error "Root access required for log cleanup"; exit 1; }
            clean_log_files
            ;;
        dev)
            clean_dev_files
            ;;
        large)
            find_large_files
            ;;
        browser)
            clean_browser_cache
            ;;
        all)
            clean_package_cache || true
            clean_temp_files || true
            clean_logs
            clean_dev_files
            ;;
        *)
            echo "Usage: $0 [package|temp|logs|dev|large|browser|all]"
            echo ""
            echo "Cleanup types:"
            echo "  package   - Clean package manager caches (apt, npm, pip, etc.)"
            echo "  temp      - Clean temporary files in /tmp and ~/.cache"
            echo "  logs      - Clean old system log files (requires sudo)"
            echo "  dev       - Find development artifacts to clean"
            echo "  large     - List large directories consuming space"
            echo "  browser   - Show browser cache cleanup instructions"
            echo "  all       - Run all safe cleanup operations"
            exit 0
            ;;
    esac
    
    # Show final summary
    show_cleanup_summary
}

# Execute main function with all arguments
main "$@"
