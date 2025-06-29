#!/usr/bin/env bash
# Claude Workflow Automation Script
# Automates: branch creation → formatting → commit → push → PR → CI wait → merge
set -euo pipefail

# Colors for output
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly DEFAULT_BASE_BRANCH="main"
readonly MAX_CI_WAIT_TIME=1800  # 30 minutes
readonly CI_CHECK_INTERVAL=30   # 30 seconds

# Global variables
BRANCH_NAME=""
COMMIT_MESSAGE=""
PR_TITLE=""
PR_BODY=""
BASE_BRANCH="$DEFAULT_BASE_BRANCH"
DRY_RUN=false
AUTO_MERGE=false
SKIP_CI_WAIT=false
VERBOSE=false

# Logging functions
log() {
    echo -e "${BLUE}[CLAUDE]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

verbose() {
    [[ "$VERBOSE" == "true" ]] && echo -e "${PURPLE}[DEBUG]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
${BOLD}Claude Workflow Automation Script${NC}

Automates the complete development workflow: branch → format → commit → PR → CI → merge

${BOLD}USAGE:${NC}
    $0 [OPTIONS] --branch BRANCH_NAME --message "COMMIT_MESSAGE"

${BOLD}REQUIRED OPTIONS:${NC}
    -b, --branch BRANCH_NAME     Name for the new branch
    -m, --message MESSAGE        Commit message

${BOLD}OPTIONAL OPTIONS:${NC}
    --title TITLE               PR title (defaults to commit message)
    --body BODY                 PR body/description
    --base BRANCH              Base branch (default: main)
    --auto-merge               Auto-merge PR after CI passes
    --skip-ci-wait             Don't wait for CI completion
    --dry-run                  Show what would be done without executing
    -v, --verbose              Verbose output
    -h, --help                 Show this help

${BOLD}EXAMPLES:${NC}
    # Basic usage
    $0 -b feature/new-alias -m "feat: add new git aliases"

    # With custom PR details and auto-merge
    $0 -b fix/startup-performance \\
       -m "perf: optimize zsh startup time" \\
       --title "🚀 Optimize Zsh Startup Performance" \\
       --body "Reduces startup time by implementing lazy loading" \\
       --auto-merge

    # Dry run to see what would happen
    $0 -b test/changes -m "test commit" --dry-run

${BOLD}WORKFLOW STEPS:${NC}
    1. 🌿 Create and checkout new branch
    2. 🎨 Format code (zsh and markdown files)
    3. 📝 Commit changes with structured message
    4. 🚀 Push branch to remote
    5. 🔗 Create pull request
    6. ⏰ Wait for CI completion (unless --skip-ci-wait)
    7. 🔄 Auto-merge if CI passes (if --auto-merge)

${BOLD}REQUIREMENTS:${NC}
    - Git repository with remote origin
    - GitHub CLI (gh) installed and authenticated
    - Proper permissions for creating PRs and merging
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -b|--branch)
                BRANCH_NAME="$2"
                shift 2
                ;;
            -m|--message)
                COMMIT_MESSAGE="$2"
                shift 2
                ;;
            --title)
                PR_TITLE="$2"
                shift 2
                ;;
            --body)
                PR_BODY="$2"
                shift 2
                ;;
            --base)
                BASE_BRANCH="$2"
                shift 2
                ;;
            --auto-merge)
                AUTO_MERGE=true
                shift
                ;;
            --skip-ci-wait)
                SKIP_CI_WAIT=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$BRANCH_NAME" ]]; then
        error "Branch name is required. Use -b or --branch option."
    fi

    if [[ -z "$COMMIT_MESSAGE" ]]; then
        error "Commit message is required. Use -m or --message option."
    fi

    # Set defaults
    if [[ -z "$PR_TITLE" ]]; then
        PR_TITLE="$COMMIT_MESSAGE"
    fi

    if [[ -z "$PR_BODY" ]]; then
        PR_BODY="This PR was automatically created by the Claude workflow script.

## Changes
- $COMMIT_MESSAGE

## Testing
- ✅ Code formatting applied
- ✅ Automated tests will run in CI

🤖 Generated with Claude Workflow Script"
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check if we're in a git repository
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        error "Not in a git repository"
    fi

    # Check if GitHub CLI is installed and authenticated
    if ! command -v gh &>/dev/null; then
        error "GitHub CLI (gh) is not installed. Please install it first."
    fi

    if ! gh auth status &>/dev/null; then
        error "GitHub CLI is not authenticated. Run 'gh auth login' first."
    fi

    # Check if remote origin exists
    if ! git remote get-url origin &>/dev/null; then
        error "No 'origin' remote found. Please add a remote repository."
    fi

    # Check for uncommitted changes on current branch
    if [[ "$(git status --porcelain)" ]]; then
        warning "Working directory has uncommitted changes"
        if [[ "$DRY_RUN" == "false" ]]; then
            read -p "Continue anyway? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                error "Aborted due to uncommitted changes"
            fi
        fi
    fi

    success "Prerequisites check passed"
}

# Execute command with dry-run support
execute() {
    local cmd="$1"
    local description="$2"

    verbose "Command: $cmd"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would execute: $description"
        return 0
    else
        log "$description"
        if eval "$cmd"; then
            success "$description completed"
            return 0
        else
            error "$description failed"
        fi
    fi
}

# Step 1: Create and checkout new branch
create_branch() {
    log "Step 1: Creating and checking out branch '$BRANCH_NAME'"

    # Ensure we're on the base branch and it's up to date
    execute "git checkout $BASE_BRANCH" "Switch to base branch ($BASE_BRANCH)"
    execute "git pull origin $BASE_BRANCH" "Update base branch"

    # Check if branch already exists
    if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
        warning "Branch '$BRANCH_NAME' already exists"
        if [[ "$DRY_RUN" == "false" ]]; then
            read -p "Delete and recreate? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                execute "git branch -D $BRANCH_NAME" "Delete existing branch"
            else
                error "Aborted due to existing branch"
            fi
        fi
    fi

    # Create and checkout new branch
    execute "git checkout -b $BRANCH_NAME" "Create and checkout new branch"
}

# Step 2: Format code
format_code() {
    log "Step 2: Formatting code"

    cd "$PROJECT_ROOT"

    # Format zsh files
    if [[ -f "scripts/format-zsh.sh" ]]; then
        execute "chmod +x scripts/format-zsh.sh" "Make zsh formatter executable"
        execute "./scripts/format-zsh.sh -d dot_config/zsh -r" "Format zsh files"
    else
        warning "Zsh formatter not found, skipping zsh formatting"
    fi

    # Format markdown files
    if [[ -f "scripts/format-markdown.sh" ]]; then
        execute "chmod +x scripts/format-markdown.sh" "Make markdown formatter executable"
        execute "./scripts/format-markdown.sh -d . -r" "Format markdown files"
    else
        warning "Markdown formatter not found, skipping markdown formatting"
    fi

    # Clean up backup files
    execute "find . -name '*.backup.*' -type f -delete 2>/dev/null || true" "Clean up backup files"

    # Check if formatting made any changes
    if [[ "$(git status --porcelain)" ]]; then
        success "Code formatting applied changes"
        verbose "Changes made:\n$(git status --porcelain)"
    else
        log "No formatting changes needed"
    fi
}

# Step 3: Commit changes
commit_changes() {
    log "Step 3: Committing changes"

    # Check if there are changes to commit
    if [[ -z "$(git status --porcelain)" ]]; then
        warning "No changes to commit"
        return 0
    fi

    # Add all changes
    execute "git add -A" "Stage all changes"

    # Create commit with structured message
    local full_commit_message="$COMMIT_MESSAGE

🤖 Generated with Claude Workflow Script

Co-Authored-By: Claude <noreply@anthropic.com>"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would commit with message:"
        echo "$full_commit_message"
    else
        # Use heredoc to handle multi-line commit message properly
        execute "git commit -m \"\$(cat <<'EOF'
$full_commit_message
EOF
)\"" "Commit changes"
    fi
}

# Step 4: Push branch
push_branch() {
    log "Step 4: Pushing branch to remote"

    execute "git push -u origin $BRANCH_NAME" "Push branch to remote"
}

# Step 5: Create pull request
create_pr() {
    log "Step 5: Creating pull request"

    local gh_cmd="gh pr create --base $BASE_BRANCH --head $BRANCH_NAME --title \"$PR_TITLE\" --body \"\$(cat <<'EOF'
$PR_BODY
EOF
)\""

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create PR with:"
        echo "  Base: $BASE_BRANCH"
        echo "  Head: $BRANCH_NAME"
        echo "  Title: $PR_TITLE"
        echo "  Body: $PR_BODY"
        return 0
    else
        local pr_url
        pr_url=$(eval "$gh_cmd")
        success "Pull request created: $pr_url"
        
        # Store PR number for later use
        PR_NUMBER=$(echo "$pr_url" | grep -o '[0-9]*$')
        verbose "PR Number: $PR_NUMBER"
        
        return 0
    fi
}

# Step 6: Wait for CI completion
wait_for_ci() {
    if [[ "$SKIP_CI_WAIT" == "true" ]]; then
        log "Skipping CI wait as requested"
        return 0
    fi

    log "Step 6: Waiting for CI completion"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would wait for CI completion on PR #$PR_NUMBER"
        return 0
    fi

    local elapsed=0
    local last_status=""

    while [[ $elapsed -lt $MAX_CI_WAIT_TIME ]]; do
        # Get CI status
        local ci_status
        ci_status=$(gh pr checks "$PR_NUMBER" --json state,conclusion --jq '.[] | select(.state == "completed") | .conclusion' 2>/dev/null || echo "pending")

        if [[ "$ci_status" != "$last_status" ]]; then
            case "$ci_status" in
                "success")
                    success "All CI checks passed!"
                    return 0
                    ;;
                "failure"|"cancelled"|"timed_out")
                    error "CI checks failed with status: $ci_status"
                    ;;
                "pending"|"")
                    log "CI checks still running... (${elapsed}s elapsed)"
                    ;;
                *)
                    log "CI status: $ci_status (${elapsed}s elapsed)"
                    ;;
            esac
            last_status="$ci_status"
        fi

        sleep $CI_CHECK_INTERVAL
        elapsed=$((elapsed + CI_CHECK_INTERVAL))

        # Show progress every 5 minutes
        if [[ $((elapsed % 300)) -eq 0 ]]; then
            log "Still waiting for CI... (${elapsed}s / ${MAX_CI_WAIT_TIME}s)"
        fi
    done

    error "Timeout waiting for CI completion (${MAX_CI_WAIT_TIME}s)"
}

# Step 7: Auto-merge PR
auto_merge_pr() {
    if [[ "$AUTO_MERGE" == "false" ]]; then
        log "Auto-merge disabled, skipping merge"
        return 0
    fi

    log "Step 7: Auto-merging pull request"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would auto-merge PR #$PR_NUMBER"
        return 0
    fi

    # Enable auto-merge with squash
    execute "gh pr merge $PR_NUMBER --squash --auto" "Enable auto-merge with squash"
    
    success "Auto-merge enabled for PR #$PR_NUMBER"
    log "PR will be automatically merged when all checks pass"
}

# Main workflow
main() {
    echo -e "${BOLD}🤖 Claude Workflow Automation${NC}"
    echo "================================="

    parse_args "$@"

    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN MODE - No actual changes will be made"
    fi

    verbose "Configuration:"
    verbose "  Branch: $BRANCH_NAME"
    verbose "  Base: $BASE_BRANCH"
    verbose "  Commit: $COMMIT_MESSAGE"
    verbose "  PR Title: $PR_TITLE"
    verbose "  Auto-merge: $AUTO_MERGE"
    verbose "  Skip CI wait: $SKIP_CI_WAIT"

    check_prerequisites

    # Execute workflow steps
    create_branch
    format_code
    commit_changes
    push_branch
    create_pr
    wait_for_ci
    auto_merge_pr

    echo
    success "🎉 Claude workflow completed successfully!"

    if [[ "$DRY_RUN" == "false" ]]; then
        log "Summary:"
        log "  ✓ Branch '$BRANCH_NAME' created and pushed"
        log "  ✓ Code formatted and committed"
        log "  ✓ Pull request created (#$PR_NUMBER)"
        if [[ "$SKIP_CI_WAIT" == "false" ]]; then
            log "  ✓ CI checks completed"
        fi
        if [[ "$AUTO_MERGE" == "true" ]]; then
            log "  ✓ Auto-merge enabled"
        fi
    fi
}

# Handle script interruption
trap 'error "Script interrupted by user"' INT TERM

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi