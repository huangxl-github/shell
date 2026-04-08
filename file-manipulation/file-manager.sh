#!/bin/bash
# Script Name: file-manager.sh
# Description: Advanced file management utilities with batch operations, smart renaming, and search
# Author: huangxl-github / Aggregated from popular shell script utilities
# Usage: ./file-manager.sh <command> [options]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Temporary directory for operations
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Command: batch-rename - Batch rename files with patterns
batch_rename() {
    if [ $# -lt 2 ]; then
        print_error "Usage: $0 batch-rename <directory> <pattern_to_replace> <replacement>"
        echo ""
        echo "Examples:"
        echo "  $0 batch-rename ~/Downloads 'IMG_.*\.jpg' 'photo_$1.JPG'"
        echo "  $0 batch-rename . 'report-(.*?)\.txt' 'document_\\1.txt'"
        return 1
    fi
    
    DIRECTORY="$1"
    PATTERN="$2"
    REPLACEMENT="${3:-RENAME_\$1}"
    
    print_info "Batch renaming in: $DIRECTORY"
    print_info "Pattern: $PATTERN → $REPLACEMENT"
    
    cd "$DIRECTORY" || exit 1
    
    # Get files matching the pattern
    FILES=($(ls -d *$PATTERN* 2>/dev/null))
    
    if [ ${#FILES[@]} -eq 0 ]; then
        print_warning "No files found matching pattern: $PATTERN"
        return
    fi
    
    echo ""
    print_info "Files to rename (${#FILES[@]}):"
    
    # Show preview
    for file in "${FILES[@]}"; do
        NEW_NAME=$(echo "$file" | sed -E "s/$PATTERN/$REPLACEMENT/")
        echo "  → $file"
        echo "     $NEW_NAME"
    done
    
    echo ""
    read -p "Continue with renaming? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Operation cancelled"
        return
    fi
    
    # Execute renaming
    for file in "${FILES[@]}"; do
        NEW_NAME=$(echo "$file" | sed -E "s/$PATTERN/$REPLACEMENT/")
        
        # Avoid name conflicts
        if [ -e "$NEW_NAME" ]; then
            print_error "Conflict: $NEW_NAME already exists"
            continue
        fi
        
        mv "$file" "$NEW_NAME"
        print_success "Renamed: $file → $NEW_NAME"
    done
    
    print_success "Batch rename completed!"
}

# Command: smart-duplicate-find - Find duplicate files by content hash
find_duplicates() {
    TARGET_DIR="${1:-.}"
    
    print_info "Finding duplicate files in: $TARGET_DIR"
    echo ""
    
    # Create temporary file for storing hashes
    HASH_FILE="$TEMP_DIR/hashes.txt"
    DUPLICATE_FILE="$TEMP_DIR/duplicates.txt"
    
    # Find all regular files and compute MD5 hashes (skip symbolic links, very large files)
    find "$TARGET_DIR" -type f ! -size +100M 2>/dev/null | while read file; do
        HASH=$(md5sum "$file" 2>/dev/null || md5 -q "$file" 2>/dev/null)
        [ -n "$HASH" ] && echo "$HASH $file" >> "$HASH_FILE"
    done
    
    # Find duplicate hashes
    print_info "Computing file hashes..."
    sort "$HASH_FILE" | cut -d' ' -f1 | uniq -d > "$DUPLICATE_FILE" || true
    
    if [ ! -s "$DUPLICATE_FILE" ]; then
        print_success "No duplicates found!"
        return
    fi
    
    print_warning "Found duplicate files:"
    echo ""
    
    DUPLICATE_COUNT=0
    TOTAL_SIZE_SAVED=0
    
    while read dup_hash; do
        # Get all files with this hash
        grep "^$dup_hash" "$HASH_FILE" | cut -d' ' -f3- > "$TEMP_DIR/dup_files.txt" || true
        FILE_LIST=($(cat "$TEMP_DIR/dup_files.txt"))
        
        if [ ${#FILE_LIST[@]} -gt 1 ]; then
            echo -e "${CYAN}Duplicate Group:${NC}"
            
            # First file kept, others will be deleted
            FIRST=true
            for filepath in "${FILE_LIST[@]}"; do
                SIZE=$(du -h "$filepath" | cut -f1)
                
                if $FIRST; then
                    echo -e "  ${GREEN}KEEP:${NC} $filepath ($SIZE)"
                    FIRST=false
                    
                    # Calculate size that would be saved by removing duplicates
                    TOTAL_SIZE_SAVED=$((TOTAL_SIZE_SAVED + $(du -k "$filepath" | cut -f1)))
                else
                    echo -e "  ${RED}DELETE:${NC} $filepath ($SIZE)"
                    ((DUPLICATE_COUNT++))
                fi
            done
            
            # Ask for deletion confirmation
            read -p "Remove duplicates in this group? (y/N): " -n 1 -r
            echo ""
            
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                SECOND=true
                for filepath in "${FILE_LIST[@]}"; do
                    if $SECOND; then
                        rm "$filepath" && print_success "Deleted: $filepath"
                    else
                        SECOND=false
                    fi
                done
            fi
            
            echo ""
        fi
    done < "$DUPLICATE_FILE"
    
    SIZE_SAVED=$(numfmt --to=iec $((TOTAL_SIZE_SAVED - ( $(du -k "$TARGET_DIR" 2>/dev/null | cut -f1) || 0 ))))
    print_info "Total duplicate files: $DUPLICATE_COUNT"
    print_info "Potential space saved: ~$SIZE_SAVED"
}

# Command: organize-files - Organize files by type into subdirectories
organize_files() {
    TARGET_DIR="${1:-.}"
    
    if [ "$TARGET_DIR" = "." ]; then
        print_warning "Warning: Will organize files in current directory $(pwd)"
        read -p "Confirm? (y/N): " -n 1 -r
        echo ""
        [[ ! $REPLY =~ ^[Yy]$ ]] && { print_warning "Cancelled"; return; }
    fi
    
    print_info "Organizing files in: $TARGET_DIR"
    
    # Define file type mappings
    declare -A FILE_GROUPS=(
        ["images"]="jpg jpeg png gif svg bmp ico webp"
        ["documents"]="pdf doc docx ppt pptx xls xlsx txt odt odg odp"
        ["videos"]="mp4 avi mkv mov wmv flv webm m4v"
        ["audio"]="mp3 wav flacaac ogg wma m4a aiff"
        ["archives"]="zip rar 7z tar gz bz2 xz tgz"
        ["code"]="py js ts java c cpp h go rs swift kt rb sh pl phpr html css"
        ["config"]="json yaml yml xml cfg ini conf toml env"
    )
    
    # Count files per category
    TOTAL_ORGANIZED=0
    
    for category in "${!FILE_GROUPS[@]}"; do
        mkdir -p "$TARGET_DIR/$category" 2>/dev/null || true
        
        EXTENSIONS="${FILE_GROUPS[$category]}"
        COUNTER=0
        
        for ext in $EXTENSIONS; do
            MATCHED=$(find "$TARGET_DIR" -maxdepth 1 -type f -name "*.$ext" 2>/dev/null | wc -l)
            
            if [ "$MATCHED" -gt 0 ]; then
                files_with_ext=$(find "$TARGET_DIR" -maxdepth 1 -type f -name "*.$ext")
                
                for file in $files_with_ext; do
                    mv "$file" "$TARGET_DIR/$category/" 2>/dev/null && ((COUNTER++)) || true
                done
            fi
        done
        
        if [ "$COUNTER" -gt 0 ]; then
            print_success "Moved $COUNTER files to $category/"
            TOTAL_ORGANIZED=$((TOTAL_ORGANIZED + COUNTER))
        fi
    done
    
    # Handle remaining files (no recognized extension or unknown type)
    REMAINING=$(find "$TARGET_DIR" -maxdepth 1 -type f ! -name "file-manager.sh" 2>/dev/null | wc -l)
    
    if [ "$REMAINING" -gt 0 ]; then
        mkdir -p "$TARGET_DIR/other"
        find "$TARGET_DIR" -maxdepth 1 -type f ! -name "file-manager.sh" -exec mv {} "$TARGET_DIR/other/" \; 2>/dev/null || true
        print_warning "Moved $REMAINING unrecognized files to other/"
    fi
    
    echo ""
    print_success "File organization completed!"
    print_info "Total files moved: $TOTAL_ORGANIZED"
    
    # Show summary
    echo -e "\n${CYAN}Organized folders:${NC}"
    ls -la "$TARGET_DIR"/*/ 2>/dev/null | grep "^d" || true
}

# Command: find-largest - Find largest files/directories
find_largest() {
    TARGET_DIR="${1:-.}"
    LIMIT=${2:-10}
    
    print_info "Finding top $LIMIT largest items in: $TARGET_DIR"
    
    echo ""
    echo -e "${CYAN}=== Largest Directories ==${NC}"
    du -ah "$TARGET_DIR" 2>/dev/null | sort -rh | head -$LIMIT | while read line; do
        SIZE=$(echo "$line" | awk '{print $1}')
        PATH=$(echo "$line" | cut -f2-)
        echo -e "  ${GREEN}$SIZE${NC} \t$PATH"
    done
    
    echo ""
    echo -e "${CYAN}=== Largest Files (individual) ==${NC}"
    find "$TARGET_DIR" -type f -exec du -h {} + 2>/dev/null | sort -rh | head -$LIMIT | while read line; do
        SIZE=$(echo "$line" | awk '{print $1}')
        PATH=$(echo "$line" | cut -f2-)
        echo -e "  ${BLUE}$SIZE${NC} \t$FILEPATH"
    done
}

# Command: find-by-pattern - Find files by name pattern with preview
find_by_pattern() {
    if [ $# -lt 1 ]; then
        print_error "Usage: $0 find-by-pattern <pattern> [directory]"
        return 1
    fi
    
    PATTERN="$1"
    TARGET_DIR="${2:-.}"
    
    RESULT=$(find "$TARGET_DIR" -type f -name "*$PATTERN*" 2>/dev/null)
    
    if [ -z "$RESULT" ]; then
        print_warning "No files found matching: $PATTERN"
        return
    fi
    
    FILE_COUNT=$(echo "$RESULT" | wc -l)
    
    echo ""
    print_success "Found $FILE_COUNT file(s):"
    echo ""
    
    echo "$RESULT" | while read filepath; do
        SIZE=$(du -h "$filepath" 2>/dev/null | cut -f1 || echo "N/A")
        MODIFIED=$(stat -c %y "$filepath" 2>/dev/null || stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$filepath" 2>/dev/null || echo "N/A")
        
        echo -e "  ${GREEN}$(basename "$filepath")${NC}"
        echo -e "    Path: $filepath"
        echo -e "    Size: $SIZE | Modified: $MODIFIED"
        echo ""
    done
    
    # Offer to delete old files if they match pattern like "*.log", "*.tmp", etc.
    if [[ $PATTERN =~ \.(log|tmp|bak|old)$ ]]; then
        read -p "Delete these files? (y/N): " -n 1 -r
        echo ""
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Delete with confirmation for each file
            echo "$RESULT" | while read filepath; do
                rm -vf "$filepath" && print_success "Deleted: $filepath" || print_error "Failed to delete: $filepath"
            done
        fi
    fi
}

# Command: show usage
show_usage() {
    echo ""
    echo "${BLUE}=== Advanced File Manager Utility ==${NC}"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Available Commands:"
    echo -e "  ${CYAN}batch-rename<DIRECTORY> <pattern> <replacement>${NC}"
    echo -e "      Batch rename files using regex patterns"
    echo "      Example: $0 batch-rename ~/Downloads 'IMG_.*\.jpg' 'photo_$1.JPG'"
    echo ""
    echo -e "  ${CYAN}find-duplicates [directory]${NC}"
    echo -e "      Find and optionally remove duplicate files by content hash"
    echo ""
    echo -e "  ${CYAN}organize-files [directory]${NC}"
    echo -e "      Automatically organize files by type into categorized folders"
    echo ""
    echo -e "  ${CYAN}find-largest [directory] [limit]${NC}"
    echo -e "      Find largest files and directories (default: top 10)"
    echo ""
    echo -e "  ${CYAN}find-by-pattern <pattern> [directory]${NC}"
    echo -e "      Find files by name pattern with detailed information"
    echo "      Example: $0 find-by-pattern '*.log' /var"
    echo ""
    echo -e "  ${CYAN}help${NC}"
    echo -e "      Show this help message"
    echo ""
}

# Main command dispatcher
case "${1:-help}" in
    batch-rename)
        shift
        batch_rename "$@"
        ;;
    find-duplicates|duplicate)
        shift
        find_duplicates "$@"
        ;;
    organize-files|organize)
        shift
        organize_files "$@"
        ;;
    find-largest|largest)
        shift
        find_largest "$@"
        ;;
    find-by-pattern|find)
        shift
        find_by_pattern "$@"
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac
