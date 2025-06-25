# Chezmoi Migration Guide

## ✅ Prerequisites Verified

Before starting migration, these have been verified through CI:
- ✅ Cross-platform compatibility (macOS/Linux)
- ✅ Business/personal environment support
- ✅ Performance optimizations working
- ✅ Error handling and fallback mechanisms
- ✅ Font installation
- ✅ Real zsh session loading
- ✅ All 6 test environments passing

## 🚀 Migration Steps

### Step 1: Backup Current Configuration

```bash
# Create backup directory
mkdir -p ~/dotfiles-backup/$(date +%Y%m%d-%H%M%S)
cd ~/dotfiles-backup/$(date +%Y%m%d-%H%M%S)

# Backup current dotfiles
cp ~/.zshenv . 2>/dev/null || echo "No .zshenv found"
cp ~/.zshrc . 2>/dev/null || echo "No .zshrc found"  
cp ~/.zprofile . 2>/dev/null || echo "No .zprofile found"
cp -r ~/.config . 2>/dev/null || echo "No .config found"

# Backup current performance
echo "Current zsh startup time:" > performance-before.txt
time (zsh -i -c exit) 2>> performance-before.txt

echo "✅ Backup completed in: $(pwd)"
```

### Step 2: Install Chezmoi

```bash
# Install chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)"

# Verify installation
chezmoi --version
```

### Step 3: Initialize Chezmoi with New Configuration

```bash
# Initialize chezmoi with the migration branch
chezmoi init https://github.com/paveg/dotfiles.git --branch chezmoi-migration

# Preview what will be changed (safe to run)
chezmoi diff
```

### Step 4: Configure Environment (Choose One)

#### For Personal Environment:
```bash
# No additional setup needed - personal is default
echo "Using personal environment configuration"
```

#### For Business/Work Environment:
```bash
# Set business environment
export BUSINESS_USE=1
echo 'export BUSINESS_USE=1' >> ~/.profile  # Persist for future sessions

# Re-initialize to pick up business configuration
chezmoi init --force
```

### Step 5: Apply Configuration

```bash
# Apply the new configuration
chezmoi apply

# Verify essential files were created
ls -la ~/.zshenv ~/.config/zsh/.zshrc ~/.config/starship.toml
```

### Step 6: Install Packages

```bash
# Install packages (includes zsh setup)
# This will run automatically via run_once_* scripts, but you can also run manually:

# On macOS:
brew bundle

# On Linux:
# Packages will be installed automatically via run_once_before_install-packages.sh
```

### Step 7: Restart Shell and Verify

```bash
# Restart your terminal or start new zsh session
exec zsh

# Verify performance (should be similar or better)
time (zsh -i -c exit)

# Test key functionality
which starship
mise --version  # Should work if installed
gh --version    # Should work if installed

# Test aliases
ll              # Should show colorized long listing
```

## 🔧 Post-Migration Verification

### Performance Check
```bash
# Measure new startup time
echo "New zsh startup time:"
for i in {1..5}; do time (zsh -i -c exit); done 2>&1 | grep real
```

### Functionality Check
```bash
# Test lazy loading (if tools are installed)
mise list       # Should work and show available versions
atuin search    # Should work for history search

# Test business environment (if applicable)
echo $BUSINESS_USE  # Should be "1" for business setup

# Test aliases and functions
ll              # Enhanced ls
opr             # 1Password reference function
rub             # Git branch cleanup function
```

### Configuration Management
```bash
# Future configuration updates
chezmoi update  # Updates from repository

# Edit configurations
chezmoi edit ~/.zshrc
chezmoi apply   # Apply changes

# Add new files to be managed
chezmoi add ~/.new-config-file
```

## 🆘 Troubleshooting

### If Something Goes Wrong

#### Rollback to Previous Configuration:
```bash
# Restore from backup
cd ~/dotfiles-backup/TIMESTAMP
cp .zshenv ~/.zshenv
cp .zshrc ~/.zshrc  
cp .zprofile ~/.zprofile
cp -r .config ~/.config

# Restart shell
exec zsh
```

#### Common Issues:

1. **Slow startup after migration:**
   ```bash
   # Enable profiling to diagnose
   ZPROFILER=1 zsh
   ```

2. **Missing commands (mise, starship, etc.):**
   ```bash
   # Install missing tools
   brew install mise starship
   # Or run the package installation script
   ```

3. **1Password plugin not working:**
   ```bash
   # Initialize 1Password plugins
   op plugin init gh
   ```

4. **Business environment not detected:**
   ```bash
   # Ensure BUSINESS_USE is set and re-initialize
   export BUSINESS_USE=1
   chezmoi init --force
   chezmoi apply
   ```

## 📊 Expected Improvements

After migration, you should see:

- ✅ **Faster startup** (lazy loading optimizations)
- ✅ **Better organization** (XDG compliance)
- ✅ **Cross-platform compatibility** (works on macOS/Linux)
- ✅ **Easy management** (chezmoi commands)
- ✅ **Automatic updates** (chezmoi update)
- ✅ **Environment separation** (personal/business)

## 📝 Next Steps

1. **Familiarize with chezmoi commands:**
   - `chezmoi edit <file>` - Edit managed files
   - `chezmoi apply` - Apply changes
   - `chezmoi update` - Update from repository
   - `chezmoi diff` - See what would change

2. **Customize for your needs:**
   - Add personal aliases to `~/.config/zsh/modules/alias.zsh`
   - Add custom functions to `~/.config/zsh/modules/func.zsh`

3. **Keep updated:**
   - Run `chezmoi update` regularly
   - Monitor performance with `zprofiler`

## 🎯 Success Criteria

Migration is successful when:
- [x] Zsh starts without errors
- [x] Performance is maintained or improved  
- [x] All expected aliases/functions work
- [x] Tools like starship, mise work correctly
- [x] Business/personal environment is correct
- [x] Package management works (brew bundle)

**Estimated migration time: 10-15 minutes**