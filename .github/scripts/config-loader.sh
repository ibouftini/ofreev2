#!/bin/bash
# Configuration loader for LaTeX workflow
# Provides functions to read configuration from latex-config.yml

set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../latex-config.yml"

# Check if yq is available, install if needed
ensure_yq() {
    if ! command -v yq &> /dev/null; then
        echo "Installing yq to local directory..."
        local yq_dir="$HOME/.local/bin"
        mkdir -p "$yq_dir"
        
        if ! wget -qO "$yq_dir/yq" https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64; then
            echo "Failed to download yq, using python as fallback"
            return 0
        fi
        chmod +x "$yq_dir/yq"
        export PATH="$yq_dir:$PATH"
        echo "yq installed to $yq_dir"
    fi
}

# Load configuration value
# Usage: get_config "path.to.value" [default]
get_config() {
    local path="$1"
    local default="${2:-}"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: Configuration file not found: $CONFIG_FILE" >&2
        exit 1
    fi
    
    local value
    
    # Try yq first
    if command -v yq &> /dev/null; then
        value=$(yq eval ".$path" "$CONFIG_FILE" 2>/dev/null || echo "null")
    else
        # Fallback to Python
        value=$(python3 -c "
import yaml
import sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = yaml.safe_load(f)
    
    path_parts = '$path'.split('.')
    current = config
    for part in path_parts:
        if isinstance(current, dict) and part in current:
            current = current[part]
        else:
            print('null')
            sys.exit(0)
    
    print(current if current is not None else 'null')
except Exception:
    print('null')
" 2>/dev/null || echo "null")
    fi
    
    if [ "$value" = "null" ] || [ -z "$value" ]; then
        if [ -n "$default" ]; then
            echo "$default"
        else
            echo "Error: Configuration value not found: $path" >&2
            exit 1
        fi
    else
        echo "$value"
    fi
}

# Get configuration array
# Usage: get_config_array "path.to.array"
get_config_array() {
    local path="$1"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: Configuration file not found: $CONFIG_FILE" >&2
        exit 1
    fi
    
    # Try yq first
    if command -v yq &> /dev/null; then
        yq eval ".$path[]" "$CONFIG_FILE" 2>/dev/null || true
    else
        # Fallback to Python
        python3 -c "
import yaml
import sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = yaml.safe_load(f)
    
    path_parts = '$path'.split('.')
    current = config
    for part in path_parts:
        if isinstance(current, dict) and part in current:
            current = current[part]
        else:
            sys.exit(0)
    
    if isinstance(current, list):
        for item in current:
            print(item)
except Exception:
    pass
" 2>/dev/null || true
    fi
}

# Get TeX Live year
get_texlive_year() {
    get_config "texlive.year" "2025"
}

# Get cache version
get_cache_version() {
    get_config "texlive.cache_version" "v6"
}

# Get max parallel jobs
get_max_parallel() {
    get_config "compilation.max_parallel" "4"
}

# Get compiler packages
# Usage: get_compiler_packages "xelatex"
get_compiler_packages() {
    local compiler="$1"
    get_config_array "compilers.${compiler}.packages"
}

# Get compiler auto-detect packages
# Usage: get_compiler_auto_detect "xelatex"
get_compiler_auto_detect() {
    local compiler="$1"
    get_config_array "compilers.${compiler}.auto_detect_packages"
}

# Get system fonts for compiler
# Usage: get_system_fonts "xelatex"
get_system_fonts() {
    local compiler="$1"
    get_config_array "compilers.${compiler}.system_fonts"
}

# Get basic TeX Live packages
get_basic_packages() {
    get_config_array "texlive.schemes.basic"
}

# Get complexity patterns
# Usage: get_complexity_patterns "bibliography"
get_complexity_patterns() {
    local category="$1"
    get_config_array "compilation.complexity_patterns.complex.${category}"
}

# Get file trigger patterns
get_trigger_patterns() {
    get_config_array "file_patterns.trigger_files"
}

# Get cleanup patterns
get_cleanup_patterns() {
    get_config_array "artifacts.cleanup_patterns"
}

# Get git configuration
get_git_user_name() {
    get_config "git.user.name" "LaTeX Compiler Bot"
}

get_git_user_email() {
    get_config "git.user.email" "action@github.com"
}

# Get retry configuration
get_git_push_retries() {
    get_config "error_handling.git_push_retries" "3"
}

get_git_push_delay() {
    get_config "error_handling.git_push_delay" "2"
}

# Get timeout values
get_timeout() {
    local timeout_type="$1"
    get_config "performance.timeouts.${timeout_type}" "10"
}

# Get artifact retention days
get_retention_days() {
    local artifact_type="$1"
    get_config "artifacts.${artifact_type}.retention_days" "7"
}

# Generate cache key
# Usage: generate_cache_key "texlive_base" "2025" "v6" "Linux"
generate_cache_key() {
    local cache_type="$1"
    local year="$2"
    local version="$3"
    local os="$4"
    local compilers="${5:-}"
    
    local pattern
    pattern=$(get_config "caching.${cache_type}.key_pattern")
    
    # Replace placeholders
    pattern="${pattern//\{year\}/$year}"
    pattern="${pattern//\{version\}/$version}"
    pattern="${pattern//\{os\}/$os}"
    pattern="${pattern//\{compilers\}/$compilers}"
    
    echo "$pattern"
}

# Check if compiler needs phase 2
# Usage: needs_phase2 "file.tex"
needs_phase2() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        echo "false"
        return
    fi
    
    # Check bibliography patterns
    if grep -qE '\\bibliography\{|\\addbibresource\{|\\printbibliography|\\cite\{|\\citep\{|\\citet\{' "$file" 2>/dev/null; then
        echo "true"
        return
    fi
    
    # Check cross-references patterns
    if grep -qE '\\ref\{|\\pageref\{|\\eqref\{|\\label\{' "$file" 2>/dev/null; then
        echo "true"
        return
    fi
    
    # Check TOC patterns
    if grep -qE '\\tableofcontents|\\listoffigures|\\listoftables' "$file" 2>/dev/null; then
        echo "true"
        return
    fi
    
    # Check for bib files in same directory
    local file_dir
    file_dir=$(dirname "$file")
    if ls "${file_dir}"/*.bib >/dev/null 2>&1; then
        echo "true"
        return
    fi
    
    echo "false"
}

# Detect compiler for file
# Usage: detect_compiler "file.tex"
detect_compiler() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        echo "pdflatex"
        return
    fi
    
    # Check for explicit directive
    local directive
    directive=$(grep -E '^[[:space:]]*%[[:space:]]*!TeX[[:space:]]+program[[:space:]]*=' "$file" 2>/dev/null | head -1 || true)
    
    if [ -n "$directive" ]; then
        if echo "$directive" | grep -qi "xelatex"; then
            echo "xelatex"
            return
        elif echo "$directive" | grep -qi "lualatex"; then
            echo "lualatex"
            return
        elif echo "$directive" | grep -qi "pdflatex"; then
            echo "pdflatex"
            return
        fi
    fi
    
    # Check for XeLaTeX patterns
    if grep -qE '\\usepackage(\[[^]]*\])?\{fontspec\}|\\usepackage(\[[^]]*\])?\{polyglossia\}|\\setmainfont\{|\\setsansfont\{|\\setmonofont\{' "$file" 2>/dev/null; then
        echo "xelatex"
        return
    fi
    
    # Check for LuaLaTeX patterns  
    if grep -qE '\\usepackage(\[[^]]*\])?\{luacode\}|\\directlua\{|\\usepackage(\[[^]]*\])?\{luatextra\}' "$file" 2>/dev/null; then
        echo "lualatex"
        return
    fi
    
    echo "pdflatex"
}

# Generate commit message
# Usage: generate_commit_message 3 1
generate_commit_message() {
    local success_count="$1"
    local failed_count="${2:-0}"
    
    local message_pattern
    message_pattern=$(get_config "git.commit.message_pattern")
    
    local failed_suffix=""
    if [ "$failed_count" -gt 0 ]; then
        local failed_suffix_pattern
        failed_suffix_pattern=$(get_config "git.commit.failed_suffix_pattern")
        failed_suffix="${failed_suffix_pattern//\{failed_count\}/$failed_count}"
    fi
    
    local timestamp
    local timestamp_format
    timestamp_format=$(get_config "git.commit.timestamp_format" "%Y-%m-%d %H:%M:%S UTC")
    timestamp=$(date -u +"$timestamp_format")
    
    # Replace placeholders
    message_pattern="${message_pattern//\{success_count\}/$success_count}"
    message_pattern="${message_pattern//\{failed_suffix\}/$failed_suffix}"
    message_pattern="${message_pattern//\{timestamp\}/$timestamp}"
    
    echo "$message_pattern"
}

# Validate configuration file
validate_config() {
    ensure_yq
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: Configuration file not found: $CONFIG_FILE" >&2
        return 1
    fi
    
    # Validate YAML syntax
    if ! yq eval '.' "$CONFIG_FILE" >/dev/null 2>&1; then
        echo "Error: Invalid YAML syntax in configuration file" >&2
        return 1
    fi
    
    # Check required sections
    local required_sections=(
        "texlive"
        "compilers"
        "compilation"
        "file_patterns"
        "caching"
    )
    
    for section in "${required_sections[@]}"; do
        if ! yq eval "has(\"$section\")" "$CONFIG_FILE" | grep -q "true"; then
            echo "Error: Missing required configuration section: $section" >&2
            return 1
        fi
    done
    
    echo "Configuration validation: PASSED"
    return 0
}

# Print configuration summary
print_config_summary() {
    echo "=== LaTeX Workflow Configuration ==="
    echo "TeX Live Year: $(get_texlive_year)"
    echo "Cache Version: $(get_cache_version)"
    echo "Max Parallel: $(get_max_parallel)"
    echo "Git User: $(get_git_user_name) <$(get_git_user_email)>"
    echo "Push Retries: $(get_git_push_retries)"
    echo "===================================="
}

# Main function for testing
main() {
    if [ $# -eq 0 ]; then
        echo "Usage: $0 <command> [args...]"
        echo "Commands:"
        echo "  validate              - Validate configuration file"
        echo "  summary               - Print configuration summary"
        echo "  get <path> [default]  - Get configuration value"
        echo "  array <path>          - Get configuration array"
        echo "  compiler <file>       - Detect compiler for file"
        echo "  phase2 <file>         - Check if file needs phase 2"
        exit 1
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        validate)
            validate_config
            ;;
        summary)
            print_config_summary
            ;;
        get)
            get_config "$@"
            ;;
        array)
            get_config_array "$1"
            ;;
        compiler)
            detect_compiler "$1"
            ;;
        phase2)
            needs_phase2 "$1"
            ;;
        *)
            echo "Unknown command: $command" >&2
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi