#!/bin/bash
# 
# Quick Utility Scripts Collection
# =================================
# A set of small, practical shell utilities for daily development and system tasks.
# 
# Each script targets a specific common need:
#   • System monitoring
#   • File operations
#   • Git workflows  
#   • Server administration
#   • Development support

set -e

# Helper function source for all scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ================================
# 1. System Info & Health Check
# =======================================

show_quick_stats() {
    echo "=== Quick System Stats ==="
    echo ""
    
    # Uptime
    printf "Uptime:       "; uptime -p 2>/dev/null || uptime | sed 's/.*up /Up /' | cut -d',' -f1,2
    
    # Load average (last minute)
    LOAD=$(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}')
    printf "Load Avg:     ${LOAD:-N/A}\n"
    
    # Memory usage
    if command -v free &> /dev/null; then
        printf "Memory:         "; free -h | grep Mem | awk '{printf "%s/%s (%s)", $3, $2, $3}'
    else
        printf "               N/A\n"
    fi
    
    # Disk space (root)
    DISK_USAGE=$(df -h / 2>/dev/null | tail -1 | awk '{print "$3/"$2}')
    printf "Disk (/):       ${DISK_USAGE:-N/A}\n"
    
    # CPU cores (Linux/Mac)
    CPU_CORES=${$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}-core"
    printf "CPU:            $CPU_CORES\n"
    
    echo ""
}

# ================================
# 2. Git Utilities  
# =======================================

git_quick_status() {
    if [ ! -d ".git" ]; then
        echo "Not a git repository!"
        return 1
    fi
    
    # Current branch
    BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
    printf "Branch: $BRANCH\n"
    
    # Uncommitted changes count
    UNCOMMITTED=$(git status --porcelain | wc -l)
    [ "$UNCOMMITTED" -gt 0 ] && printf "Changes: %u uncommitted files\n" "$UNCOMMITTED" || printf "Status: Clean repository\n"
    
    # AHEAD/BEHIND remote check (if tracking exists)
    if git rev-parse --is-in-work-tree &>/dev/null 2>&1; then
        REMOTE_STATUS=$(git status --porcelain | grep -E "^(##|\{)" | wc -l)
        
        if [ "$REMOTE_STATUS" -gt 0 ]; then
            # Check if ahead or behind
            AHEAD=$(git rev-list HEAD...@{u} --count 2>/dev/null || echo 0)
            BEHIND=$(git rev-list @{u}...HEAD --count 2>/dev/null || echo 0)
            
            [ "$AHEAD" -gt 0 ] && printf "Ahead of remote: +%d commits\n" "$AHEAD"
            [ "$BEHIND" -gt 0 ] && printf "Behind remote:   +%d commits\n" "$BEHIND"
        fi
    fi
    
    echo ""
}

# ================================
# 3. Process Monitoring (Top 5)
# =======================================

top_processes() {
    COUNT="${1:-5}"
    
    echo "=== Top ${COUNT} Processes by Memory ==="
    echo ""
    
    if command -v ps &> /dev/null; then
        ps aux | head -2
    
        echo ""
        printf "%-6s %-8s %-8s %-10s %s\n" "PID" "USER" "CPU%" "MEM%" "COMMAND"
        printf "%-6s %-8s %-8s %-10s %s\n" "---" ----"---" ---"--------" "---"----
        
        # Get top processes sorted by memory (%MEM -k), skip header
        ps aux --sort=-%mem ${COUNT} | tail -$COUNT 2>/dev/null | while read USER PID CPU MEM REST_OF_LINE; do
            CMD=$(echo "$REST_OF_LINE" | awk '{print $1}' | sed 's:.*/::' || echo "$REST_OF_LINE")
            printf "%-6s %-8s %-8s %-10s %s\n" "$PID" "$USER" "${CPU%.*}" "${MEM%.*}" "${CMD:0:25}"
        done
        
        echo ""
    else
        echo "Process information not available."
    fi
}

# ================================
# 4. Find Recent Files
# =======================================

recent_files() {
    DIRECTORY="${1:-$HOME/workspace}"
    FILE_TYPE="${2:-*}"
    DAYS_OLD="${3:-7}"
    
    printf "Finding files in %s matching pattern: %s\n" "$DIRECTORY" "$FILE_TYPE"
    printf "(Modified within last %d days)\n\n" "$DAYS_OLD"
    
    if [ ! -d "$DIRECTORY" ]; then
        echo "Directory does not exist: $DIRECTORY"
        return 1
    fi
    
    # Find files (sorted by modification time, newest first)
    find "$DIRECTORY" -maxdepth 3 -type f -name "*${FILE_TYPE}*" -mtime -$DAYS_OLD \
        -printf "%T+ %p\n" 2>/dev/null | sort -r | head -10 || \
        find "$DIRECTORY" -maxdepth 3 -type f -name "*${FILE_TYPE}*" -mtime -$DAYS_OLD -ls 2>/dev/null | sort -k8-9rn | head -10
    
    echo ""
}

# ================================
# 5. Disk Usage Summary  
# =======================================

disk_summary() {
    DIRECTORY="${1:-/}"
    
    printf "=== Disk Usage for: %s ===\n\n" "$DIRECTORY"
    
    # Top-level folders usage (show size, human-readable)
    if [ -x "$DIRECTORY" ]; then
        du -sh "$DIRECTORY"/*/ 2>/dev/null | sort -rh | head -5 | while read SIZE PATH; do
            printf "📁 %s\t%s\n" "$SIZE" "${PATH#./}"
        done || true
    fi
    
    echo ""
    
    # Filesystem mount info (root filesystem)
    if command -v df &> /dev/null; then
        echo -e "Filesystem Mount Summary:"
        df -h --output=source,target,size,used,avail,pcent 2>/dev/null | head -3 || \
            df -h 2>/dev/null | head -4
    fi
    
    echo ""
}

# ================================
# 6. Create Project Template
# =======================================

create_project() {
    PROJECT_NAME="${1:-my-project}"
    
    if [ -d "$PROJECT_NAME" ]; then
        echo "Directory already exists: $PROJECT_NAME"
        read -p "Remove and create new? (y/N): " -n 1 -r
        echo ""
        [[ ! $REPLY =~ ^[Yy]$ ]] && { echo "Cancelled."; return; }
        rm -rf "$PROJECT_NAME"
    fi
    
    mkdir -p "$PROJECT_NAME"/{src,tests,dist,docs}
    
    # Basic project files
    cat > "$PROJECT_NAME/README.md" << EOF
# $PROJECT_NAME

> Add your project description here

## Setup

\`\`\`bash
git clone <repository-url>
cd $PROJECT_NAME
npm install  # or whatever package manager
\`\`\`

## Development

\`\`\`bash
npm run dev
\`\`\`

## Testing

\`\`\`bash
npm test
\`\`\`

## License

MIT
EOF

    # Basic .gitignore template
    cat > "$PROJECT_NAME/.gitignore" << EOF
# Dependencies
node_modules/
vendor/

# Build outputs
dist/
build/
out/
.target/

# IDE
.vscode/.idea /.swp *.swo /~ *~

# OS
.DS_Store
Thumbs.db

# Logs
logs/
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Environment
.env
.env.local
.env.*.local
EOF
    
    # Simple package.json (for Node.js projects)
    cat > "$PROJECT_NAME/package.json" << EOF
{
  "name": "$PROJECT_NAME",
  "version": "1.0.0",
  "description": "",
  "main": "index.js",
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "keywords": [],
  "author": "",
  "license": "MIT"
}
EOF
    
    # Basic .gitattributes
    cat > "$PROJECT_NAME/.gitattributes" << EOF
*.sh text eol=lf
Makefile text eol=lf

# Ensure consistent line endings for text files
text text eol=lf
binary binary eol=crlf
EOF
    
    echo "✅ Project template created: $PROJECT_NAME"
    ls -lh "$PROJECT_NAME"/
}

# ================================
# Main Script Entry Point  
# =======================================

case "${1:-quick-stats}" in
    stats|system)
        show_quick_stats
        ;;
    git|gs)
        git_quick_status
        ;;
    top|processes)
        shift
        top_processes "$@"
        ;;
    recent|r)
        shift
        recent_files "$@"
        ;;
    disk|du)
        shift
        disk_summary "$@"
        ;;
    newproject|create)
        shift
        create_project "$@"
        ;;
    all|full)
        show_quick_stats
        echo "" > /dev/null
        top_processes 3
        echo "" > /dev/null
        recent_files "." "*" 7
        ;;
    help|--help|-h)
        echo "Available Commands:"
        echo "  stats/system               Show system health statistics"
        echo "  git/gs                     Quick git repository status"
        echo "  top [count]                Show top processes (default: 5)"
        echo "  recent [dir][pattern][days] Find recently modified files"
        echo "  disk [path]                Show disk usage summary"
        echo "  newproject [name]          Create project template structure"
        echo "  all                        Run all quick checks"
        echo ""
        ;;
    *)
        echo "Unknown command: $1. Use '$0 help' for options."
        exit 1
        ;;
esac
