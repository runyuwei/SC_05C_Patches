#!/bin/bash

# ============================================================================
# Flexible Patch Application Script
# Supports custom configuration and optional branch creation
# ============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration file path
CONFIG_FILE="${SCRIPT_DIR}/patch_config_flexible.conf"

# Load configuration file early
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Default settings (if configuration file doesn't exist)
DEFAULT_USER="${GERRIT_USER:-$(whoami)}"
DEFAULT_HOST="${GERRIT_HOST:-icggerrit.corp.intel.com}"
DEFAULT_PORT="${GERRIT_PORT:-29418}"
DEFAULT_BRANCH="${PATCH_BRANCH:-$(date +%Y%m%d)_patches}"

# Current configuration
USER="$DEFAULT_USER"
GERRIT_HOST="$DEFAULT_HOST"
GERRIT_PORT="$DEFAULT_PORT"
BRANCH_NAME="$DEFAULT_BRANCH"
CREATE_BRANCH=true

# Configuration will be loaded from patch_config_flexible.conf
# Arrays will be declared in the configuration file

# Color output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/patch_apply_$(date +%Y%m%d_%H%M%S).log"

# Logging functions
log_info() {
    local msg="[INFO] $1"
    echo -e "${BLUE}${msg}${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" >> "$LOG_FILE"
}

log_success() {
    local msg="[SUCCESS] $1"
    echo -e "${GREEN}${msg}${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" >> "$LOG_FILE"
}

log_warning() {
    local msg="[WARNING] $1"
    echo -e "${YELLOW}${msg}${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" >> "$LOG_FILE"
}

log_error() {
    local msg="[ERROR] $1"
    echo -e "${RED}${msg}${NC}" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" >> "$LOG_FILE"
}

# Load configuration file
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log_info "Configuration file found: $CONFIG_FILE"
        
        # Update variables from config file (arrays already loaded at script start)
        USER="${GERRIT_USER:-$USER}"
        GERRIT_HOST="${GERRIT_HOST:-$GERRIT_HOST}"
        GERRIT_PORT="${GERRIT_PORT:-$GERRIT_PORT}"
        BRANCH_NAME="${BRANCH_NAME:-$DEFAULT_BRANCH}"
        
        log_success "Configuration variables updated"
    else
        log_warning "Configuration file not found: $CONFIG_FILE"
        log_info "Using default configuration"
    fi
}

# Display current configuration
show_config() {
    echo ""
    log_info "Current configuration:"
    echo "  Username: $USER"
    echo "  Gerrit: $GERRIT_HOST:$GERRIT_PORT"
    if [ "$CREATE_BRANCH" = "true" ]; then
        echo "  Branch name: $BRANCH_NAME"
    else
        echo "  Branch strategy: Apply patches on current branch"
    fi
    echo "  Config file: $CONFIG_FILE"
    echo "  Log file: $LOG_FILE"
    echo ""
    
    log_info "Repositories and patches to process:"
    
    # Simple approach - just show what we have
    if [ "${#PATCH_CONFIGS[@]}" -eq 0 ]; then
        echo "  No patch configurations found!"
    else
        # Use printf to safely display the configurations
        for repo in "${REPO_ORDER[@]}"; do
            # Try a different approach to access the array
            if [[ "${PATCH_CONFIGS[$repo]+isset}" == "isset" ]]; then
                local config="${PATCH_CONFIGS[$repo]}"
                local repo_name="${config%%:*}"
                local patch_list="${config#*:}"
                echo "  $repo -> $repo_name: $patch_list"
            fi
        done
    fi
    echo ""
}

# Display help information
show_help() {
    cat << EOF
Usage: $0 [options]

Options:
  -u, --user USER         Specify Gerrit username (current: $USER)
  -b, --branch BRANCH     Specify branch name (current: $BRANCH_NAME)
  --no-branch             Don't create new branch, apply patches on current branch
  -h, --host HOST         Specify Gerrit host (current: $GERRIT_HOST)
  -p, --port PORT         Specify Gerrit port (current: $GERRIT_PORT)
  -c, --config FILE       Specify configuration file (current: $CONFIG_FILE)
  -d, --dry-run           Preview mode, don't execute actual operations
  -f, --force             Force execution, skip confirmation
  -r, --repo REPO         Only process specified repository
  --show-config           Display current configuration and exit
  --help                  Display this help information

Configuration file:
  You can customize patch lists through configuration file, see: patch_config_flexible.conf

Examples:
  $0 --dry-run                          # Preview all operations
  $0 --user myname --branch test_0916   # Specify user and branch
  $0 --no-branch --repo io              # Process only io repository on current branch
  $0 --config my_patches.conf           # Use custom configuration file

EOF
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    for cmd in git ssh jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Installation suggestion: sudo apt install ${missing_deps[*]}"
        return 1
    fi
    
    return 0
}

# Test Gerrit connection
test_gerrit_connection() {
    log_info "Testing Gerrit connection: $USER@$GERRIT_HOST:$GERRIT_PORT"
    
    if ! ssh -p "$GERRIT_PORT" -o ConnectTimeout=10 -o BatchMode=yes "$USER@$GERRIT_HOST" gerrit version &>/dev/null; then
        log_error "Cannot connect to Gerrit server"
        log_info "Please check:"
        log_info "  1. Username is correct: $USER"
        log_info "  2. SSH key is configured"
        log_info "  3. Network connection is working"
        return 1
    fi
    
    log_success "Gerrit connection test successful"
    return 0
}

# Apply single patch
apply_single_patch() {
    local patch_id="$1"
    local repo_name="$2"
    local dry_run="$3"
    
    patch_id=$(echo "$patch_id" | sed 's/[^0-9]//g')
    
    if [ -z "$patch_id" ]; then
        return 0
    fi
    
    log_info "Processing patch: $patch_id"
    
    local temp_dir temp_json
    temp_dir=$(mktemp -d)
    temp_json="${temp_dir}/patch_${patch_id}.json"
    
    trap "rm -rf '$temp_dir'" RETURN
    
    # Query patch information
    if ! ssh -p "$GERRIT_PORT" "$USER@$GERRIT_HOST" gerrit query --current-patch-set --format=json "$patch_id" > "$temp_json"; then
        log_error "Cannot query patch $patch_id"
        return 1
    fi
    
    # Parse patchset number
    local patchset
    patchset=$(jq -r 'select(.currentPatchSet != null) | .currentPatchSet.number' "$temp_json" 2>/dev/null | head -1)
    
    if [ -z "$patchset" ] || [ "$patchset" = "null" ]; then
        log_error "Cannot parse patchset information for patch $patch_id"
        return 1
    fi
    
    # Build fetch reference
    local change_suffix="${patch_id: -2}"
    local fetch_ref="refs/changes/${change_suffix}/${patch_id}/${patchset}"
    local fetch_cmd="git fetch ssh://${USER}@${GERRIT_HOST}:${GERRIT_PORT}/${repo_name} $fetch_ref"
    
    if [ "$dry_run" = "true" ]; then
        log_info "[DRY-RUN] Will execute: $fetch_cmd"
        log_info "[DRY-RUN] Will execute: git cherry-pick FETCH_HEAD"
        return 0
    fi
    
    # Execute fetch and cherry-pick
    if eval "$fetch_cmd" && git cherry-pick FETCH_HEAD; then
        log_success "Successfully applied patch: $patch_id"
        return 0
    else
        log_error "Failed to apply patch: $patch_id"
        return 1
    fi
}

# Process single repository
process_repository() {
    local work_dir="$1"
    local repo_name="$2"
    local patch_list="$3"
    local dry_run="$4"
    local original_dir="$PWD"
    
    log_info "========================================="
    log_info "Processing repository: $work_dir ($repo_name)"
    log_info "Patch list: $patch_list"
    
    if [ ! -d "$work_dir" ]; then
        log_error "Directory does not exist: $work_dir"
        return 1
    fi
    
    cd "$work_dir" || return 1
    
    if ! git rev-parse --git-dir &>/dev/null; then
        log_error "$work_dir is not a git repository"
        cd "$original_dir"
        return 1
    fi
    
    # Check working directory status
    if ! git diff --quiet || ! git diff --cached --quiet; then
        log_error "Working directory has uncommitted changes, please commit or stash first"
        cd "$original_dir"
        return 1
    fi
    
    # Branch handling
    if [ "$CREATE_BRANCH" = "true" ]; then
        if [ "$dry_run" = "true" ]; then
            log_info "[DRY-RUN] Will create/switch to branch: $BRANCH_NAME"
        else
            if git checkout -b "$BRANCH_NAME" 2>/dev/null; then
                log_success "Created new branch: $BRANCH_NAME"
            elif git checkout "$BRANCH_NAME" 2>/dev/null; then
                log_warning "Switched to existing branch: $BRANCH_NAME"
            else
                log_error "Cannot create or switch to branch: $BRANCH_NAME"
                cd "$original_dir"
                return 1
            fi
        fi
    else
        log_info "Applying patches on current branch: $(git branch --show-current)"
    fi
    
    # Apply patches
    local success_count=0
    local fail_count=0
    
    IFS=' ' read -ra PATCHES <<< "$patch_list"
    for patch_id in "${PATCHES[@]}"; do
        if [ -n "$patch_id" ]; then
            if apply_single_patch "$patch_id" "$repo_name" "$dry_run"; then
                ((success_count++))
            else
                ((fail_count++))
            fi
        fi
    done
    
    log_info "Repository $work_dir processing completed: success $success_count, failed $fail_count"
    cd "$original_dir"
    return $fail_count
}

# Main function
main() {
    local dry_run=false
    local force=false
    local target_repo=""
    local show_config_only=false
    local cmd_user=""
    local cmd_branch=""
    local cmd_host=""
    local cmd_port=""
    
    # Parse command line arguments first
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--user)
                cmd_user="$2"
                shift 2
                ;;
            -b|--branch)
                cmd_branch="$2"
                CREATE_BRANCH=true
                shift 2
                ;;
            --no-branch)
                CREATE_BRANCH=false
                shift
                ;;
            -h|--host)
                cmd_host="$2"
                shift 2
                ;;
            -p|--port)
                cmd_port="$2"
                shift 2
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -r|--repo)
                target_repo="$2"
                shift 2
                ;;
            --show-config)
                show_config_only=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Load configuration from file
    load_config
    
    # Override with command line arguments (command line takes precedence)
    [ -n "$cmd_user" ] && USER="$cmd_user"
    [ -n "$cmd_branch" ] && BRANCH_NAME="$cmd_branch"
    [ -n "$cmd_host" ] && GERRIT_HOST="$cmd_host"
    [ -n "$cmd_port" ] && GERRIT_PORT="$cmd_port"
    
    # If only showing configuration
    if [ "$show_config_only" = "true" ]; then
        show_config
        exit 0
    fi
    
    log_info "========================================="
    log_info "Flexible Patch Application Tool"
    log_info "========================================="
    
    show_config
    
    if [ "$dry_run" = "true" ]; then
        log_warning "Preview mode - will not execute actual operations"
    fi
    
    # Check dependencies
    if ! check_dependencies; then
        return 1
    fi
    
    # Test connection
    if ! test_gerrit_connection; then
        return 1
    fi
    
    # Confirm operation
    if [ "$force" != "true" ] && [ "$dry_run" != "true" ]; then
        echo ""
        log_warning "About to start applying patches"
        read -p "Confirm to continue? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled"
            exit 0
        fi
    fi
    
    # Process repositories
    local success_repos=0
    local fail_repos=0
    
    for repo_dir in "${REPO_ORDER[@]}"; do
        if [ -n "$target_repo" ] && [ "$target_repo" != "$repo_dir" ]; then
            continue
        fi
        
        if [[ -v "PATCH_CONFIGS[$repo_dir]" ]]; then
            local config="${PATCH_CONFIGS[$repo_dir]}"
            local repo_name="${config%%:*}"
            local patch_list="${config#*:}"
            
            if process_repository "$repo_dir" "$repo_name" "$patch_list" "$dry_run"; then
                ((success_repos++))
            else
                ((fail_repos++))
            fi
            echo ""
        fi
    done
    
    # Summary
    echo "========================================="
    if [ "$dry_run" = "true" ]; then
        log_info "Preview completed!"
    else
        log_info "Patch application completed!"
    fi
    log_info "Success: $success_repos, Failed: $fail_repos"
    log_info "Detailed log: $LOG_FILE"
    echo "========================================="
    
    return $fail_repos
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
