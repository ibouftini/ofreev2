#!/bin/bash
# Test script for LaTeX workflow components
# Validates actions and configuration before deployment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Test configuration loader
test_config_loader() {
    log_info "Testing configuration loader..."
    
    local config_script="$SCRIPT_DIR/config-loader.sh"
    
    if [ ! -f "$config_script" ]; then
        log_error "Configuration loader script not found: $config_script"
        return 1
    fi
    
    # Test validation
    if ! "$config_script" validate; then
        log_error "Configuration validation failed"
        return 1
    fi
    
    # Test basic configuration access
    local texlive_year
    texlive_year=$("$config_script" get "texlive.year" "2025")
    if [ "$texlive_year" != "2025" ]; then
        log_error "Failed to read TeX Live year: got '$texlive_year', expected '2025'"
        return 1
    fi
    
    # Test array access
    local basic_packages
    basic_packages=$("$config_script" array "texlive.schemes.basic")
    if [ -z "$basic_packages" ]; then
        log_error "Failed to read basic packages array"
        return 1
    fi
    
    log_info "Configuration loader tests: PASSED"
    return 0
}

# Test action structure
test_action_structure() {
    log_info "Testing action structure..."
    
    local actions_dir="$REPO_ROOT/.github/actions"
    local expected_actions=(
        "setup-texlive"
        "detect-changes"
        "compile-document"
    )
    
    for action in "${expected_actions[@]}"; do
        local action_file="$actions_dir/$action/action.yml"
        
        if [ ! -f "$action_file" ]; then
            log_error "Action file not found: $action_file"
            return 1
        fi
        
        # Validate YAML syntax
        if ! python3 -c "import yaml; yaml.safe_load(open('$action_file'))" 2>/dev/null; then
            log_error "Invalid YAML syntax in action: $action_file"
            return 1
        fi
        
        # Check required fields
        if ! grep -q "name:" "$action_file"; then
            log_error "Missing 'name' field in action: $action_file"
            return 1
        fi
        
        if ! grep -q "description:" "$action_file"; then
            log_error "Missing 'description' field in action: $action_file"
            return 1
        fi
        
        log_info "Action validation passed: $action"
    done
    
    log_info "Action structure tests: PASSED"
    return 0
}

# Test workflow syntax
test_workflow_syntax() {
    log_info "Testing workflow syntax..."
    
    local workflow_file="$REPO_ROOT/.github/workflows/latex-optimized.yml"
    
    if [ ! -f "$workflow_file" ]; then
        log_error "Workflow file not found: $workflow_file"
        return 1
    fi
    
    # Validate YAML syntax
    if ! python3 -c "import yaml; yaml.safe_load(open('$workflow_file'))" 2>/dev/null; then
        log_error "Invalid YAML syntax in workflow: $workflow_file"
        return 1
    fi
    
    # Check required workflow fields
    local required_fields=(
        "name:"
        "on:"
        "jobs:"
    )
    
    for field in "${required_fields[@]}"; do
        if ! grep -q "$field" "$workflow_file"; then
            log_error "Missing required field '$field' in workflow"
            return 1
        fi
    done
    
    # Check job dependencies
    if ! grep -q "needs:" "$workflow_file"; then
        log_warn "No job dependencies found - may not be using parallel execution"
    fi
    
    # Check matrix strategy
    if ! grep -q "matrix:" "$workflow_file"; then
        log_error "No matrix strategy found in workflow"
        return 1
    fi
    
    log_info "Workflow syntax tests: PASSED"
    return 0
}

# Create test LaTeX files
create_test_files() {
    log_info "Creating test LaTeX files..."
    
    local test_dir="$REPO_ROOT/test"
    mkdir -p "$test_dir/simple" "$test_dir/complex" "$test_dir/xelatex"
    
    # Simple document (in its own directory)
    cat > "$test_dir/simple/simple.tex" << 'EOF'
\documentclass{article}
\usepackage{amsmath}
\begin{document}
\title{Simple Test Document}
\author{Test Author}
\date{\today}
\maketitle

This is a simple test document.

\section{Introduction}
This document tests basic compilation.

\section{Math}
Here is a simple equation:
\begin{equation}
E = mc^2
\end{equation}

\end{document}
EOF

    # Complex document with bibliography (in its own directory)
    cat > "$test_dir/complex/complex.tex" << 'EOF'
\documentclass{article}
\usepackage{amsmath}
\usepackage{cite}
\begin{document}
\title{Complex Test Document}
\author{Test Author}
\date{\today}
\maketitle

\tableofcontents

\section{Introduction}
This document tests complex compilation with references.

See \cite{test2025}.

\section{Math}
Equation \ref{eq:energy} shows Einstein's famous formula.

\begin{equation}
\label{eq:energy}
E = mc^2
\end{equation}

\section{Conclusion}
This concludes our test document.

\bibliography{test}
\bibliographystyle{plain}
\end{document}
EOF

    # Bibliography file (in complex directory)
    cat > "$test_dir/complex/test.bib" << 'EOF'
@article{test2025,
    title={Test Article},
    author={Test Author},
    journal={Test Journal},
    year={2025}
}
EOF

    # XeLaTeX document (in its own directory)
    cat > "$test_dir/xelatex/xelatex.tex" << 'EOF'
% !TeX program = xelatex
\documentclass{article}
\usepackage{fontspec}
\usepackage{unicode-math}
\setmainfont{Liberation Serif}
\begin{document}
\title{XeLaTeX Test Document}
\author{Test Author}
\date{\today}
\maketitle

This document tests XeLaTeX compilation with unicode support.

Unicode characters: α β γ δ ε ζ η θ

\section{Math}
\begin{equation}
∀x ∈ ℝ : x² ≥ 0
\end{equation}

\end{document}
EOF

    log_info "Test files created in: $test_dir"
}

# Test compiler detection
test_compiler_detection() {
    log_info "Testing compiler detection..."
    
    local config_script="$SCRIPT_DIR/config-loader.sh"
    local test_dir="$REPO_ROOT/test"
    
    # Test simple document (should detect pdflatex)
    local detected_compiler
    detected_compiler=$("$config_script" compiler "$test_dir/simple/simple.tex")
    if [ "$detected_compiler" != "pdflatex" ]; then
        log_error "Wrong compiler detected for simple.tex: got '$detected_compiler', expected 'pdflatex'"
        return 1
    fi
    
    # Test XeLaTeX document (should detect xelatex)
    detected_compiler=$("$config_script" compiler "$test_dir/xelatex/xelatex.tex")
    if [ "$detected_compiler" != "xelatex" ]; then
        log_error "Wrong compiler detected for xelatex.tex: got '$detected_compiler', expected 'xelatex'"
        return 1
    fi
    
    log_info "Compiler detection tests: PASSED"
    return 0
}

# Test phase 2 detection
test_phase2_detection() {
    log_info "Testing phase 2 detection..."
    
    local config_script="$SCRIPT_DIR/config-loader.sh"
    local test_dir="$REPO_ROOT/test"
    
    # Test simple document (should not need phase 2)  
    # Run in subshell with proper environment
    local needs_phase2
    needs_phase2=$(PATH="$HOME/.local/bin:$PATH" "$config_script" phase2 "$test_dir/simple/simple.tex" 2>/dev/null)
    
    if [ "$needs_phase2" != "false" ]; then
        log_error "Wrong phase 2 detection for simple.tex: got '$needs_phase2', expected 'false'"
        
        # Additional debugging
        log_error "Debug info:"
        log_error "  File exists: $([ -f "$test_dir/simple/simple.tex" ] && echo "yes" || echo "no")"
        if [ -f "$test_dir/simple/simple.tex" ]; then
            log_error "  Bibliography check: $(grep -qE '\\bibliography\{|\\addbibresource\{|\\printbibliography|\\cite\{|\\citep\{|\\citet\{' "$test_dir/simple/simple.tex" && echo "found" || echo "not found")"
            log_error "  Reference check: $(grep -qE '\\ref\{|\\pageref\{|\\eqref\{|\\label\{' "$test_dir/simple/simple.tex" && echo "found" || echo "not found")"
            log_error "  TOC check: $(grep -qE '\\tableofcontents|\\listoffigures|\\listoftables' "$test_dir/simple/simple.tex" && echo "found" || echo "not found")"
            log_error "  Bib files: $(ls "$test_dir/simple"/*.bib >/dev/null 2>&1 && echo "found" || echo "not found")"
        fi
        return 1
    fi
    
    # Test complex document (should need phase 2)
    needs_phase2=$(PATH="$HOME/.local/bin:$PATH" "$config_script" phase2 "$test_dir/complex/complex.tex" 2>/dev/null)
    if [ "$needs_phase2" != "true" ]; then
        log_error "Wrong phase 2 detection for complex.tex: got '$needs_phase2', expected 'true'"
        return 1
    fi
    
    log_info "Phase 2 detection tests: PASSED"
    return 0
}

# Test action inputs/outputs
test_action_interfaces() {
    log_info "Testing action interfaces..."
    
    local actions_dir="$REPO_ROOT/.github/actions"
    
    # Test setup-texlive action
    local setup_action="$actions_dir/setup-texlive/action.yml"
    if ! grep -q "inputs:" "$setup_action"; then
        log_error "setup-texlive action missing inputs section"
        return 1
    fi
    if ! grep -q "outputs:" "$setup_action"; then
        log_error "setup-texlive action missing outputs section"
        return 1
    fi
    
    # Test detect-changes action
    local detect_action="$actions_dir/detect-changes/action.yml"
    if ! grep -q "outputs:" "$detect_action"; then
        log_error "detect-changes action missing outputs section"
        return 1
    fi
    if ! grep -q "matrix:" "$detect_action"; then
        log_error "detect-changes action missing matrix output"
        return 1
    fi
    
    # Test compile-document action
    local compile_action="$actions_dir/compile-document/action.yml"
    if ! grep -q "inputs:" "$compile_action"; then
        log_error "compile-document action missing inputs section"
        return 1
    fi
    if ! grep -q "file:" "$compile_action"; then
        log_error "compile-document action missing file input"
        return 1
    fi
    
    log_info "Action interface tests: PASSED"
    return 0
}

# Test directory structure
test_directory_structure() {
    log_info "Testing directory structure..."
    
    local required_dirs=(
        ".github/actions/setup-texlive"
        ".github/actions/detect-changes"
        ".github/actions/compile-document"
        ".github/workflows"
        ".github/scripts"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$REPO_ROOT/$dir" ]; then
            log_error "Required directory not found: $dir"
            return 1
        fi
    done
    
    local required_files=(
        ".github/latex-config.yml"
        ".github/scripts/config-loader.sh"
        ".github/workflows/latex-optimized.yml"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$REPO_ROOT/$file" ]; then
            log_error "Required file not found: $file"
            return 1
        fi
    done
    
    log_info "Directory structure tests: PASSED"
    return 0
}

# Performance simulation test
test_performance_simulation() {
    log_info "Testing performance simulation..."
    
    # Simulate matrix generation for multiple documents
    local test_files=(
        "test/simple/simple.tex"
        "test/complex/complex.tex"
        "test/xelatex/xelatex.tex"
    )
    
    local matrix_json="["
    local first=true
    
    for file in "${test_files[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            matrix_json="$matrix_json,"
        fi
        
        local basename
        basename=$(basename "$file" .tex)
        local compiler="pdflatex"
        local complexity="simple"
        local needs_phase2="false"
        
        if [[ "$file" == *"complex"* ]]; then
            complexity="complex"
            needs_phase2="true"
        fi
        
        if [[ "$file" == *"xelatex"* ]]; then
            compiler="xelatex"
        fi
        
        matrix_json="$matrix_json{\"file\":\"$file\",\"compiler\":\"$compiler\",\"complexity\":\"$complexity\",\"needs-phase2\":$needs_phase2,\"basename\":\"$basename\"}"
    done
    
    matrix_json="$matrix_json]"
    
    # Validate JSON
    if ! echo "$matrix_json" | python3 -m json.tool >/dev/null 2>&1; then
        log_error "Generated matrix is not valid JSON"
        return 1
    fi
    
    local doc_count
    doc_count=$(echo "$matrix_json" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")
    
    log_info "Performance simulation: $doc_count documents would be processed in parallel"
    log_info "Performance simulation tests: PASSED"
    return 0
}

# Cleanup test files
cleanup_test_files() {
    log_info "Cleaning up test files..."
    
    local test_dir="$REPO_ROOT/test"
    if [ -d "$test_dir" ]; then
        rm -rf "$test_dir"
        log_info "Test directory removed: $test_dir"
    fi
}

# Run integration test
run_integration_test() {
    log_info "Running integration test..."
    
    # This would be a dry-run of the actual workflow
    # For now, we'll simulate the key components
    
    local config_script="$SCRIPT_DIR/config-loader.sh"
    
    # Test 1: Configuration loading
    if ! "$config_script" validate; then
        log_error "Integration test failed: Configuration validation"
        return 1
    fi
    
    # Test 2: Compiler detection across all test files
    local test_files=(
        "test/simple/simple.tex"
        "test/complex/complex.tex"
        "test/xelatex/xelatex.tex"
    )
    
    for file in "${test_files[@]}"; do
        if [ -f "$REPO_ROOT/$file" ]; then
            local compiler
            compiler=$("$config_script" compiler "$REPO_ROOT/$file")
            log_info "Integration test: $file -> $compiler"
        fi
    done
    
    log_info "Integration tests: PASSED"
    return 0
}

# Main test runner
main() {
    log_info "Starting LaTeX workflow tests..."
    echo "========================================="
    
    local failed_tests=0
    local total_tests=0
    
    # List of test functions
    local tests=(
        test_directory_structure
        test_config_loader
        test_action_structure
        test_workflow_syntax
        test_action_interfaces
    )
    
    # Create test files for the tests that need them
    create_test_files
    
    # Add tests that require test files
    tests+=(
        test_compiler_detection
        test_phase2_detection
        test_performance_simulation
        run_integration_test
    )
    
    # Run all tests
    for test_func in "${tests[@]}"; do
        total_tests=$((total_tests + 1))
        echo ""
        
        if $test_func; then
            log_info "✓ $test_func"
        else
            log_error "✗ $test_func"
            failed_tests=$((failed_tests + 1))
        fi
    done
    
    # Cleanup
    cleanup_test_files
    
    echo ""
    echo "========================================="
    log_info "Test Results:"
    log_info "  Total tests: $total_tests"
    log_info "  Passed: $((total_tests - failed_tests))"
    
    if [ $failed_tests -gt 0 ]; then
        log_error "  Failed: $failed_tests"
        log_error "Some tests failed!"
        return 1
    else
        log_info "  Failed: 0"
        log_info "All tests passed!"
        return 0
    fi
}

# Check if script is run directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi