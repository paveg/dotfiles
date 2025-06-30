# Enhanced Lazy Loading System

This document describes the enhanced lazy loading system implemented to optimize zsh startup performance while maintaining full functionality.

## Overview

The enhanced lazy loading system extends the existing optimization patterns with:

- **Context-aware loading**: Tools load only when relevant to the current project
- **Enhanced tool initialization**: Improved versions of existing lazy loading patterns
- **Performance monitoring**: Detailed tracking and benchmarking capabilities
- **Project detection**: Automatic detection of project types to optimize tool loading

## Architecture

### Module Structure

```
dot_config/zsh/modules/tools/
├── lazy-loading.zsh        # Context-aware lazy loading for development tools
├── enhanced-lazy-tools.zsh # Enhanced versions of existing tool patterns
└── plugin.zsh             # Existing zinit-based plugin management
```

### Key Components

1. **Project Context Detection** (`lazy-loading.zsh`)
   - Detects project types: Node.js, Rust, Python, Docker, Kubernetes, etc.
   - Updates context on directory changes
   - Provides `is_project_context()` helper function

2. **Enhanced Tool Loading** (`enhanced-lazy-tools.zsh`)
   - Improves existing mise, atuin, starship lazy loading
   - Adds performance tracking and caching
   - Provides better session detection

3. **Development Tool Wrappers** (`lazy-loading.zsh`)
   - Container tools: docker, docker-compose, kubectl, helm
   - Cloud tools: aws, gcloud
   - Package managers: npm, yarn, pnpm, poetry
   - Context-aware completion loading

## Performance Benefits

### Baseline Measurements

Based on performance analysis:

- **Current startup time**: 160-180ms (already well-optimized)
- **Target improvement**: 30-50% reduction in non-development contexts
- **Context-aware loading**: Tools only initialize when relevant

### Expected Impact

| Scenario                  | Before | After     | Improvement |
| ------------------------- | ------ | --------- | ----------- |
| Non-development directory | 160ms  | 100-120ms | ~30%        |
| Node.js project           | 160ms  | 140ms     | ~15%        |
| Container project         | 160ms  | 130ms     | ~20%        |
| Clean environment         | 160ms  | 80-100ms  | ~40%        |

## Usage

### Environment Variables

```bash
# Enable/disable lazy loading (default: enabled)
export LAZY_LOADING_ENABLED=1

# Enable debug output for lazy loading
export LAZY_LOADING_DEBUG=1

# Track tool usage for optimization hints
export TRACK_TOOL_USAGE=1
```

### Project Context

The system automatically detects project types based on files:

- **Node.js**: `package.json`, `pnpm-workspace.yaml`, `yarn.lock`
- **Rust**: `Cargo.toml`, `Cargo.lock`
- **Python**: `requirements.txt`, `pyproject.toml`, `setup.py`
- **Docker**: `Dockerfile`, `docker-compose.yml`
- **Kubernetes**: `k8s/` directory, `kubectl.yaml`, `$KUBECONFIG`
- **Cloud**: `.gcloudignore`, `.aws/`, `$AWS_PROFILE`

### Commands

```bash
# View lazy loading statistics
lazy-stats

# Toggle lazy loading on/off
lazy-toggle

# Warm up all lazy tools (for testing)
lazy-warm

# Show tool usage statistics
tool-stats

# Benchmark startup performance
./scripts/benchmark-startup.sh
```

## Tool Behavior

### Container Tools

**Docker & Docker Compose**

- Load only in directories with `Dockerfile` or `docker-compose.yml`
- Completion loads on first use or in Docker contexts
- Aliases available after first initialization

**Kubernetes Tools (kubectl, helm)**

- Load only in k8s contexts or when `KUBECONFIG` is set
- kubectl aliases (`k`, `kg`, `kd`, etc.) available after initialization
- Expensive completions delayed until needed

### Package Managers

**Node.js Tools (npm, yarn, pnpm)**

- Load only in Node.js projects (detected by `package.json`)
- Error message suggests `command npm` to force execution
- Completions load with tool initialization

**Python Tools (poetry)**

- Load only in Python projects
- Similar forcing mechanism available

### Cloud Tools

**AWS CLI**

- Loads in projects with AWS configuration
- Handles both v1 and v2 completion formats
- Context detection via `.aws/` or `$AWS_PROFILE`

**Google Cloud**

- Expensive completion only loads when needed
- Multiple completion source detection
- Context detection via `.gcloudignore` or `.gcloud/`

## Enhanced Existing Tools

### mise (Runtime Manager)

- **Project-aware loading**: Immediate loading if `.mise.toml` or version files present
- **Session detection**: Better logic for tmux/zellij contexts
- **Performance tracking**: Measures initialization time

### atuin (History Search)

- **Smart session detection**: More intelligent immediate vs lazy loading
- **Improved key binding**: Better Ctrl+R integration
- **Performance monitoring**: Tracks initialization timing

### starship (Prompt)

- **Caching**: Caches initialization for faster subsequent loads
- **Cache invalidation**: Regenerates when starship binary updates
- **Performance tracking**: Monitors initialization time

## Development

### Adding New Lazy Tools

1. **Check tool availability**:

   ```zsh
   if is_exist_command newtool; then
       # Setup lazy loading
   fi
   ```

2. **Create lazy wrapper**:

   ```zsh
   _lazy_newtool() {
       local args=("$@")
       unfunction _lazy_newtool newtool

       # Load completions if needed
       if is_project_context "relevant"; then
           eval "$(newtool completion zsh)"
       fi

       command newtool "${args[@]}"
   }
   function newtool() { _lazy_newtool "$@"; }
   ```

3. **Add performance tracking**:
   ```zsh
   local start_time="$(date +%s.%3N)"
   # ... initialization ...
   local end_time="$(date +%s.%3N)"
   LAZY_LOADING_TIMINGS[newtool]="$(echo "$end_time - $start_time" | bc || echo "0")"
   ```

### Testing

```bash
# Run comprehensive tests
./tests/test-lazy-loading.sh --verbose

# Run performance benchmarks
./scripts/benchmark-startup.sh --iterations 20 --profile

# Test specific scenarios
DOTS_DEBUG=1 zsh -l  # Debug mode
LAZY_LOADING_DEBUG=1 zsh -l  # Lazy loading debug
```

## Configuration Options

### Disabling Lazy Loading

To disable for specific tools or globally:

```bash
# Disable globally
export LAZY_LOADING_ENABLED=0

# Force tool execution (bypass lazy loading)
command docker --version  # Always works regardless of context
```

### Performance Tuning

```bash
# Enable detailed performance tracking
export DOTS_DEBUG=1
export LAZY_LOADING_DEBUG=1

# Track tool usage for optimization
export TRACK_TOOL_USAGE=1

# Benchmark different configurations
./scripts/benchmark-startup.sh --compare
```

## Migration

The enhanced lazy loading is designed to be:

- **Backward compatible**: Existing functionality preserved
- **Opt-in**: Can be disabled if needed
- **Non-breaking**: Falls back gracefully if tools are missing

### Migration Steps

1. **Apply the changes**: `chezmoi apply`
2. **Test startup**: `DOTS_DEBUG=1 zsh -l`
3. **Benchmark performance**: `./scripts/benchmark-startup.sh`
4. **Adjust if needed**: Use environment variables to tune behavior

## Troubleshooting

### Common Issues

**Tool not loading in project context**:

```bash
# Check project detection
echo $PROJECT_CONTEXT

# Force context update
cd . && echo $PROJECT_CONTEXT
```

**Performance regression**:

```bash
# Benchmark comparison
./scripts/benchmark-startup.sh --compare

# Check lazy loading stats
lazy-stats
```

**Tool not available**:

```bash
# Force execution
command docker --version

# Check tool availability
is_exist_command docker && echo "available" || echo "missing"
```

### Debug Mode

Enable comprehensive debugging:

```bash
export DOTS_DEBUG=1
export LAZY_LOADING_DEBUG=1
zsh -l
```

This will show:

- Module loading times
- Lazy tool initialization
- Project context detection
- Performance metrics

## Future Enhancements

Potential areas for further optimization:

1. **Machine Learning**: Learn from usage patterns to optimize loading
2. **Background Initialization**: Pre-load tools in background
3. **Advanced Caching**: Cache more expensive initializations
4. **Dynamic Optimization**: Adjust behavior based on performance metrics
5. **Integration with External Tools**: Hooks for IDE/editor integration

## Performance Monitoring

The system includes comprehensive performance monitoring:

- **Startup time tracking**: Color-coded feedback
- **Per-tool timing**: Individual initialization times
- **Usage analytics**: Track which tools are used most
- **Benchmark utilities**: Compare different configurations
- **Historical data**: Track performance over time (optional)

This enables continuous optimization and prevents performance regressions.
