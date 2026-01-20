#!/bin/bash
# install.sh - Create symlinks for AI agent configuration files
# Usage: ./install.sh <agent_type> [options] [target_dir]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# === Agent mapping definitions ===
# Returns space-separated list of files for each agent type
get_agent_files() {
  case "$1" in
    claude) echo "CLAUDE.md .claude" ;;
    codex)  echo "AGENTS.md .codex" ;;
    gemini) echo "GEMINI.md .gemini" ;;
    *)      return 1 ;;
  esac
}

# Common files (used by all agents)
COMMON_FILES="ralph.sh ralph-prompt.md"

# Valid agent types
VALID_AGENTS="claude codex gemini"

# Files that should be renamed with .ralph suffix if they already exist
RENAMEABLE_FILES="AGENTS.md CLAUDE.md GEMINI.md"

# Files that should be skipped (not linked)
SKIP_FILES=".DS_Store .gitignore"

# === Color output ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# === Functions ===
usage() {
  cat << EOF
Usage: $(basename "$0") <agent_type> [options] [target_dir]

Create symlinks for AI agent configuration files.

Agent types:
  claude    Claude Code configuration
  codex     OpenAI Codex configuration
  gemini    Google Gemini configuration

Options:
  -f, --force     Overwrite existing files/symlinks
  -n, --dry-run   Show what would be done without executing
  -u, --unlink    Remove symlinks instead of creating them
  -h, --help      Show this help message

Arguments:
  target_dir      Target directory for symlinks (default: current directory)

Examples:
  $(basename "$0") claude                    # Create Claude symlinks in current dir
  $(basename "$0") codex /path/to/project    # Create Codex symlinks in specified dir
  $(basename "$0") gemini -f                 # Force overwrite existing files
  $(basename "$0") claude -u                 # Remove Claude symlinks
  $(basename "$0") codex -n                  # Dry run for Codex

Notes:
  - If a file or directory already exists, the symlink will be created with
    a .ralph suffix instead (e.g., CLAUDE.md -> CLAUDE.ralph.md, skills -> skills.ralph).
  - If a directory (e.g., .claude) already exists, files inside will be linked
    individually rather than replacing the entire directory.
  - Existing files are never deleted - use -f to force overwrite if needed.
EOF
  exit 0
}

error() {
  echo -e "${RED}Error: $1${NC}" >&2
  exit 1
}

info() {
  echo -e "${BLUE}$1${NC}"
}

success() {
  echo -e "${GREEN}$1${NC}"
}

warn() {
  echo -e "${YELLOW}$1${NC}"
}

is_valid_agent() {
  for agent in $VALID_AGENTS; do
    if [[ "$agent" == "$1" ]]; then
      return 0
    fi
  done
  return 1
}

is_renameable() {
  local file="$1"
  for renameable in $RENAMEABLE_FILES; do
    if [[ "$renameable" == "$file" ]]; then
      return 0
    fi
  done
  return 1
}

should_skip() {
  local file="$1"
  for skip in $SKIP_FILES; do
    if [[ "$skip" == "$file" ]]; then
      return 0
    fi
  done
  return 1
}

# Get renamed path with .ralph suffix
# For .md files: CLAUDE.md -> CLAUDE.ralph.md
# For other files: skills -> skills.ralph
get_renamed_path() {
  local filename="$1"
  if [[ "$filename" == *.md ]]; then
    local basename="${filename%.md}"
    echo "${basename}.ralph.md"
  else
    echo "${filename}.ralph"
  fi
}

# Link a single file (with optional auto-rename if target exists)
# Arguments:
#   $1 - source_path
#   $2 - target_path
#   $3 - display_name
#   $4 - auto_rename (optional, "true" to rename with .ralph suffix if exists)
link_file() {
  local source_path="$1"
  local target_path="$2"
  local display_name="$3"
  local auto_rename="${4:-false}"

  if [[ -L "$target_path" ]]; then
    # Existing symlink
    local existing_target
    existing_target="$(readlink "$target_path")"
    if [[ "$existing_target" == "$source_path" ]]; then
      echo "Already linked: $display_name"
      return 0
    fi
    # Check if symlink is broken (target doesn't exist)
    local is_broken=false
    if [[ ! -e "$target_path" ]]; then
      is_broken=true
    fi
    if $FORCE || $is_broken; then
      if $DRY_RUN; then
        if $is_broken; then
          echo "Would replace broken symlink: $display_name"
        else
          echo "Would replace symlink: $display_name"
        fi
      else
        rm "$target_path"
        ln -s "$source_path" "$target_path"
        if $is_broken; then
          success "Replaced broken symlink: $display_name"
        else
          success "Replaced: $display_name"
        fi
      fi
    else
      # Symlink exists with different target - skip (don't overwrite user's symlink)
      info "Symlink exists (different target), skipping: $display_name"
    fi
  elif [[ -e "$target_path" ]]; then
    # Existing file/directory (not a symlink)
    if $FORCE; then
      if $DRY_RUN; then
        echo "Would replace: $display_name"
      else
        rm -rf "$target_path"
        ln -s "$source_path" "$target_path"
        success "Replaced: $display_name"
      fi
    elif [[ "$auto_rename" == "true" ]]; then
      # Auto-rename: use .ralph suffix
      local item_name
      item_name="$(basename "$target_path")"
      local renamed
      renamed="$(get_renamed_path "$item_name")"
      local parent_dir
      parent_dir="$(dirname "$target_path")"
      local renamed_target="$parent_dir/$renamed"
      local renamed_display
      renamed_display="$(dirname "$display_name")/$renamed"
      info "File exists, using renamed: $display_name -> $renamed"
      link_file "$source_path" "$renamed_target" "$renamed_display" "false"
    else
      warn "File exists, use -f to overwrite: $display_name"
    fi
  else
    # Create new symlink
    if $DRY_RUN; then
      echo "Would create: $display_name -> $source_path"
    else
      # Create parent directory if needed
      local parent_dir
      parent_dir="$(dirname "$target_path")"
      if [[ ! -d "$parent_dir" ]]; then
        mkdir -p "$parent_dir"
      fi
      ln -s "$source_path" "$target_path"
      success "Created: $display_name -> $source_path"
    fi
  fi
}

# Unlink a single file
unlink_file() {
  local target_path="$1"
  local display_name="$2"

  if [[ -L "$target_path" ]]; then
    if $DRY_RUN; then
      echo "Would remove symlink: $display_name"
    else
      rm "$target_path"
      success "Removed: $display_name"
    fi
  elif [[ -e "$target_path" ]]; then
    warn "Not a symlink, skipping: $display_name"
  else
    echo "Already absent: $display_name"
  fi
}

# Link directory contents recursively
# - Source symlinks: if target exists, rename with .ralph suffix
# - Source directories: if target exists, recurse; otherwise create
# - Source files: if target exists, rename with .ralph suffix
link_directory_contents() {
  local source_dir="$1"
  local target_dir="$2"
  local prefix="$3"

  # Create target directory if it doesn't exist
  if [[ ! -d "$target_dir" ]]; then
    if $DRY_RUN; then
      echo "Would create directory: $target_dir"
    else
      mkdir -p "$target_dir"
      success "Created directory: $prefix"
    fi
  fi

  # Process each item in the source directory
  for source_item in "$source_dir"/*; do
    [[ -e "$source_item" ]] || continue  # Skip if no matches

    local item_name
    item_name="$(basename "$source_item")"
    local target_item="$target_dir/$item_name"
    local display_name="$prefix/$item_name"

    if [[ -L "$source_item" ]]; then
      # Source is a symlink - link it with auto-rename if target exists
      link_file "$source_item" "$target_item" "$display_name" "true"
    elif [[ -d "$source_item" ]]; then
      # Source is a real directory
      if [[ -d "$target_item" ]]; then
        # Target directory exists (real or symlink to directory) - recurse into it
        link_directory_contents "$source_item" "$target_item" "$display_name"
      elif [[ -e "$target_item" || -L "$target_item" ]]; then
        # Target exists but is not a directory - skip
        warn "Target exists (not a directory), skipping: $display_name"
      else
        # Target doesn't exist - link the whole directory
        link_file "$source_item" "$target_item" "$display_name" "false"
      fi
    else
      # Source is a regular file - link it with auto-rename if target exists
      link_file "$source_item" "$target_item" "$display_name" "true"
    fi
  done

  # Also process hidden files
  for source_item in "$source_dir"/.*; do
    local item_name
    item_name="$(basename "$source_item")"
    # Skip . and ..
    [[ "$item_name" == "." || "$item_name" == ".." ]] && continue
    [[ -e "$source_item" ]] || continue
    # Skip files that should not be linked
    should_skip "$item_name" && continue

    local target_item="$target_dir/$item_name"
    local display_name="$prefix/$item_name"

    if [[ -L "$source_item" ]]; then
      # Source is a symlink - link it with auto-rename if target exists
      link_file "$source_item" "$target_item" "$display_name" "true"
    elif [[ -d "$source_item" ]]; then
      # Source is a real directory
      if [[ -d "$target_item" ]]; then
        # Target directory exists (real or symlink to directory) - recurse into it
        link_directory_contents "$source_item" "$target_item" "$display_name"
      elif [[ -e "$target_item" || -L "$target_item" ]]; then
        warn "Target exists (not a directory), skipping: $display_name"
      else
        link_file "$source_item" "$target_item" "$display_name" "false"
      fi
    else
      # Source is a regular file - link it with auto-rename if target exists
      link_file "$source_item" "$target_item" "$display_name" "true"
    fi
  done
}

# Unlink directory contents recursively
# Also removes .ralph suffixed symlinks
unlink_directory_contents() {
  local source_dir="$1"
  local target_dir="$2"
  local prefix="$3"

  [[ -d "$target_dir" ]] || return 0

  for source_item in "$source_dir"/* "$source_dir"/.*; do
    local item_name
    item_name="$(basename "$source_item")"
    [[ "$item_name" == "." || "$item_name" == ".." ]] && continue
    [[ -e "$source_item" ]] || continue

    local target_item="$target_dir/$item_name"
    local display_name="$prefix/$item_name"

    if [[ -d "$source_item" && ! -L "$source_item" ]]; then
      if [[ -d "$target_item" && ! -L "$target_item" ]]; then
        unlink_directory_contents "$source_item" "$target_item" "$display_name"
      else
        unlink_file "$target_item" "$display_name"
        # Also try to unlink renamed version
        local renamed
        renamed="$(get_renamed_path "$item_name")"
        unlink_file "$target_dir/$renamed" "$prefix/$renamed"
      fi
    else
      unlink_file "$target_item" "$display_name"
      # Also try to unlink renamed version
      local renamed
      renamed="$(get_renamed_path "$item_name")"
      unlink_file "$target_dir/$renamed" "$prefix/$renamed"
    fi
  done
}

# === Parse arguments ===
AGENT_TYPE=""
TARGET_DIR=""
FORCE=false
DRY_RUN=false
UNLINK=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--force)
      FORCE=true
      shift
      ;;
    -n|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -u|--unlink)
      UNLINK=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      error "Unknown option: $1"
      ;;
    *)
      if [[ -z "$AGENT_TYPE" ]]; then
        AGENT_TYPE="$1"
      elif [[ -z "$TARGET_DIR" ]]; then
        TARGET_DIR="$1"
      else
        error "Too many arguments"
      fi
      shift
      ;;
  esac
done

# Validate agent type
if [[ -z "$AGENT_TYPE" ]]; then
  error "Agent type is required. Use -h for help."
fi

if ! is_valid_agent "$AGENT_TYPE"; then
  error "Invalid agent type: $AGENT_TYPE. Valid types: $VALID_AGENTS"
fi

# Set default target directory
if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="$(pwd)"
fi

# Resolve to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || error "Target directory does not exist: $TARGET_DIR"

# Prevent linking to source directory
if [[ "$TARGET_DIR" == "$SCRIPT_DIR" ]]; then
  error "Target directory cannot be the same as source directory"
fi

# === Build file list ===
AGENT_FILES="$(get_agent_files "$AGENT_TYPE")"
FILES_TO_LINK="$COMMON_FILES $AGENT_FILES"

# === Execute operations ===
info "Agent type: $AGENT_TYPE"
info "Source: $SCRIPT_DIR"
info "Target: $TARGET_DIR"
if $DRY_RUN; then
  warn "Dry run mode - no changes will be made"
fi
echo ""

for item in $FILES_TO_LINK; do
  SOURCE_PATH="$SCRIPT_DIR/$item"
  TARGET_PATH="$TARGET_DIR/$item"

  # Check source exists
  if [[ ! -e "$SOURCE_PATH" ]]; then
    warn "Source not found, skipping: $item"
    continue
  fi

  if $UNLINK; then
    # === Unlink mode ===
    if [[ -d "$SOURCE_PATH" && ! -L "$SOURCE_PATH" ]]; then
      # Source is a directory - check if we need to unlink contents
      if [[ -d "$TARGET_PATH" && ! -L "$TARGET_PATH" ]]; then
        unlink_directory_contents "$SOURCE_PATH" "$TARGET_PATH" "$item"
      else
        unlink_file "$TARGET_PATH" "$item"
      fi
    else
      unlink_file "$TARGET_PATH" "$item"
      # Also try to unlink renamed version for renameable files
      if is_renameable "$item"; then
        renamed="$(get_renamed_path "$item")"
        unlink_file "$TARGET_DIR/$renamed" "$renamed"
      fi
    fi
  else
    # === Link mode ===
    if [[ -d "$SOURCE_PATH" && ! -L "$SOURCE_PATH" ]]; then
      # Source is a directory
      if [[ -d "$TARGET_PATH" && ! -L "$TARGET_PATH" ]]; then
        # Target directory exists - link contents recursively
        info "Directory exists, linking contents: $item"
        link_directory_contents "$SOURCE_PATH" "$TARGET_PATH" "$item"
      else
        # Target doesn't exist or is not a directory
        link_file "$SOURCE_PATH" "$TARGET_PATH" "$item"
      fi
    elif is_renameable "$item" && [[ -e "$TARGET_PATH" && ! -L "$TARGET_PATH" ]]; then
      # Renameable file exists as regular file - use renamed version
      renamed="$(get_renamed_path "$item")"
      renamed_target="$TARGET_DIR/$renamed"
      info "File exists, using renamed symlink: $item -> $renamed"
      link_file "$SOURCE_PATH" "$renamed_target" "$renamed"
    else
      # Regular file or symlink
      link_file "$SOURCE_PATH" "$TARGET_PATH" "$item"
    fi
  fi
done

echo ""
if $DRY_RUN; then
  info "Dry run complete. Run without -n to apply changes."
else
  if $UNLINK; then
    success "Unlink complete."
  else
    success "Symlinks created successfully."
  fi
fi
