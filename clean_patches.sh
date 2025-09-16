#!/bin/bash

# ============================================================================
# Repository Cleanup Script
# Reset all repositories to clean master state
# ============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration file
CONFIG_FILE="${SCRIPT_DIR}/patch_config_flexible.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Repository directories to clean (loaded from config file, with fallback)
if [ -n "${REPO_ORDER:-}" ]; then
    REPO_DIRS=("${REPO_ORDER[@]}")
else
    # Fallback to hardcoded list if config not available
    REPO_DIRS=("common" "io" "apps" "framework/device-mgr" "components/ipu/drivers" "components/ipu/mw" "components/ipu/gdf")
fi

# Color output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Global variables
readonly LOG_FILE="${SCRIPT_DIR}/repo_clean_$(date +%Y%m%d_%H%M%S).log"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case "$level" in
        "ERROR")   echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        "WARN")    echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "INFO")    echo -e "${BLUE}[INFO]${NC} $message" ;;
        *)         echo "$message" ;;
    esac
}

# Print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean all repositories to pristine master state

OPTIONS:
    --dry-run         Preview operations without executing
    --force           Execute cleanup without confirmation
    --repo REPO       Clean only specific repository
    --help            Show this help message

EXAMPLES:
    $0 --dry-run      # Preview what will be cleaned
    $0 --force        # Clean all repositories without confirmation
    $0 --repo io      # Clean only the io repository

EOF
}

# Repository cleanup function
clean_repository() {
    local repo_dir="$1"
    local dry_run="${2:-false}"
    
    log "INFO" "Processing repository: $repo_dir"
    
    if [ ! -d "$repo_dir" ]; then
        log "WARN" "Directory does not exist: $repo_dir"
        return 0
    fi
    
    cd "$repo_dir" || {
        log "ERROR" "Cannot change to directory: $repo_dir"
        return 1
    }
    
    # Check if it's a git repository
    if [ ! -d ".git" ]; then
        log "WARN" "Not a git repository: $repo_dir"
        cd "$SCRIPT_DIR"
        return 0
    fi
    
    if [ "$dry_run" = "true" ]; then
        log "INFO" "[DRY RUN] Would clean repository: $repo_dir"
        
        # Show current status
        local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        local branches=$(git branch --format='%(refname:short)' 2>/dev/null | grep -v '^master$' | wc -l)
        local uncommitted=$(git status --porcelain 2>/dev/null | wc -l)
        
        echo "  Current branch: $current_branch"
        echo "  Non-master branches: $branches"
        echo "  Uncommitted changes: $uncommitted"
        
        if [ "$branches" -gt 0 ]; then
            echo "  Branches to delete:"
            git branch --format='%(refname:short)' 2>/dev/null | grep -v '^master$' | sed 's/^/    /'
        fi
        
        cd "$SCRIPT_DIR"
        return 0
    fi
    
    # Abort any ongoing git operations
    if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ] || [ -f ".git/MERGE_HEAD" ] || [ -f ".git/CHERRY_PICK_HEAD" ]; then
        log "INFO" "Aborting ongoing git operations..."
        git rebase --abort 2>/dev/null || true
        git merge --abort 2>/dev/null || true
        git cherry-pick --abort 2>/dev/null || true
    fi
    
    # Discard all uncommitted changes
    log "INFO" "Discarding uncommitted changes..."
    git reset --hard HEAD
    git clean -fd
    
    # Switch to master branch if not already there
    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ "$current_branch" != "master" ]; then
        log "INFO" "Switching to master branch..."
        git checkout master || {
            log "ERROR" "Failed to checkout master branch in $repo_dir"
            cd "$SCRIPT_DIR"
            return 1
        }
    fi
    
    # Delete all non-master branches
    local branches_to_delete=$(git branch --format='%(refname:short)' 2>/dev/null | grep -v '^master$')
    if [ -n "$branches_to_delete" ]; then
        log "INFO" "Deleting non-master branches..."
        echo "$branches_to_delete" | while read -r branch; do
            if [ -n "$branch" ]; then
                log "INFO" "Deleting branch: $branch"
                git branch -D "$branch" 2>/dev/null || log "WARN" "Failed to delete branch: $branch"
            fi
        done
    fi
    
    # Reset master to remote state
    log "INFO" "Resetting master to remote state..."
    git reset --hard origin/master 2>/dev/null || git reset --hard HEAD
    
    # Pull latest changes
    log "INFO" "Pulling latest changes..."
    if git ls-remote --exit-code origin >/dev/null 2>&1; then
        git pull origin master || log "WARN" "Failed to pull from remote"
    else
        log "WARN" "No remote configured or accessible"
    fi
    
    log "SUCCESS" "Repository cleaned: $repo_dir"
    cd "$SCRIPT_DIR"
    return 0
}

# Main execution function
main() {
    local dry_run=false
    local force=false
    local specific_repo=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --repo)
                specific_repo="$2"
                shift 2
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Determine repositories to process
    local repos_to_process=()
    if [ -n "$specific_repo" ]; then
        repos_to_process=("$specific_repo")
    else
        repos_to_process=("${REPO_DIRS[@]}")
    fi
    
    # Show configuration
    log "INFO" "Repository Cleanup Script"
    log "INFO" "Log file: $LOG_FILE"
    log "INFO" "Processing repositories: ${repos_to_process[*]}"
    
    if [ "$dry_run" = "true" ]; then
        log "INFO" "DRY RUN MODE - No changes will be made"
    elif [ "$force" != "true" ]; then
        echo ""
        echo "This will reset ALL repositories to clean master state:"
        echo "- Discard all uncommitted changes"
        echo "- Delete all non-master branches" 
        echo "- Reset master to remote state"
        echo ""
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "INFO" "Operation cancelled by user"
            exit 0
        fi
    fi
    
    echo ""
    log "INFO" "Starting cleanup process..."
    
    # Process each repository
    local success_count=0
    local total_count=${#repos_to_process[@]}
    
    for repo in "${repos_to_process[@]}"; do
        echo ""
        if clean_repository "$repo" "$dry_run"; then
            ((success_count++))
        fi
    done
    
    echo ""
    log "SUCCESS" "Cleanup completed: $success_count/$total_count repositories processed"
    
    if [ "$dry_run" = "false" ]; then
        echo ""
        echo "Summary:"
        for repo in "${repos_to_process[@]}"; do
            if [ -d "$repo" ]; then
                cd "$repo"
                local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
                local branch_count=$(git branch 2>/dev/null | wc -l)
                local uncommitted=$(git status --porcelain 2>/dev/null | wc -l)
                echo "  $repo: branch=$current_branch, branches=$branch_count, uncommitted=$uncommitted"
                cd "$SCRIPT_DIR"
            fi
        done
    fi
}

# Run main function
main "$@"
