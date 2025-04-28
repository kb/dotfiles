# Dotfiles

This repository contains my personal dotfiles for macOS, managed using GNU Stow. These dotfiles provide configuration for various tools and applications, making it easy to set up a consistent development environment across different machines.

## Overview

This dotfiles repository is organized by application or tool, with each directory containing configuration files for a specific tool. The repository uses GNU Stow to create symbolic links from your home directory to the configuration files in this repository, making it easy to manage and update your dotfiles.

## Dependencies

- macOS
- [Homebrew](https://brew.sh/)
- [GNU Stow](https://www.gnu.org/software/stow/)
- [Oh My Zsh](https://ohmyz.sh/)
- [1Password](https://1password.com/) (Passwords, ssh keys, and git commit signing)
- [Emacs 30+](https://www.gnu.org/software/emacs/)

## Installation

1. Install and configure Prerequisites
    1. Run `xcode-select --install` from terminal
    1. Install [1Password](https://1password.com/downloads/mac)
    1. Set ENV VAR for 1Password service account 

   ```bash
   security add-generic-password -U -a ${USER} -D "environment variable" -s "${1}" -w "${secret}"
   ```

1. Copy/Download this repository to your new computer (assuming you don't have git functionality yet)

1. Run the setup script:

```bash
make setup
```

This will:
- Install Homebrew if not already installed
- Install GNU Stow via Homebrew
- Stow all configuration files
- Install packages from Brewfile
- Install Oh My Zsh
- Set some macOS preferences

## Post Installation

1. Update Alfred to point to iCloud folder location so preferences are sync'd

### Manual Installation

If you prefer to install components individually:

```bash
# Install Homebrew
make install-homebrew

# Install GNU Stow
make brew-stow

# Stow all configuration files
make stow

# Install packages from Brewfile
make brew-bundle

# Install Oh My Zsh
make install-oh-my-zsh

# Set macOS preferences
make mac-prefs
```

You can also stow individual configurations:

```bash
make stow-zsh
make stow-git
make stow-emacs
# etc.
```

## Directory Structure

- **1password/**: 1Password configuration
- **emacs/**: Emacs configuration based on Emacs Bedrock
- **git/**: Git configuration with 1Password integration for commit signing
- **homebrew/**: Brewfile for managing packages and applications
- **scripts/**: Custom utility scripts
- **ssh/**: SSH configuration
- **zsh/**: Zsh shell configuration with Oh My Zsh

## Configuration Details

### Homebrew

The `homebrew/dot-Brewfile` contains a list of packages, applications, and dependencies that are installed using Homebrew. It includes:

- CLI tools and utilities (e.g., circleci, heroku, jq, postgresql, rbenv)
- Mac App Store applications via the 'mas' CLI (e.g., 1Password for Safari, Things 3)
- Applications not available in the App Store, installed via Homebrew Cask (e.g., Alfred, Docker, iTerm2)

### Zsh

The Zsh configuration is minimal with the most notable part being secret management via 1Password.

### Git

The Git configuration includes:
- User information
- GPG configuration for commit signing using SSH keys via 1Password
- Git LFS (Large File Storage) configuration
- GitHub username
- Pull behavior (merge, not rebase)
- Default branch name (main)

### Emacs

The Emacs configuration is based on Emacs Bedrock, a minimal but comprehensive Emacs configuration. It includes:

- Basic settings for a better user experience
- Discovery aids like which-key
- Minibuffer/completion settings
- Interface enhancements
- Tab-bar configuration
- Dark theme (modus-vivendi)
- Development tools configuration (tree-sitter, Magit, language modes, Eglot)

### Scripts

The repository includes several utility scripts:

- `uuid`: Generates a UUID, converts it to lowercase, and copies it to the clipboard
- `random-password`: Generates a secure random password
- `set-*`: Set operation scripts (difference, symmetric-difference, union)
- `keychain-environment-variables`: Manages environment variables stored in the macOS Keychain
- Various project-specific scripts

## Customization

### Adding New Dotfiles

1. Create a new directory for the application/tool:

```bash
mkdir -p newapp
```

2. Add your configuration files with the "dot-" prefix:

```bash
touch newapp/dot-config
```

3. Add a new stow target to the Makefile:

```makefile
stow-newapp:
	stow newapp --dotfiles
```

4. Update the `stow` target in the Makefile to include your new target:

```makefile
stow: stow-scripts stow-zsh stow-ssh stow-git stow-1pw stow-homebrew stow-emacs stow-newapp
	@echo "All dotfiles have been stowed"
```

5. Stow your new configuration:

```bash
make stow-newapp
```

### Updating Existing Dotfiles

1. Make changes to the configuration files in the repository
2. Run `make stow` to update the symbolic links

## macOS Preferences

The Makefile includes targets for setting some macOS preferences:

- `show-extensions`: Shows filename extensions by default
- `disable-natural-scroll`: Disables natural scroll direction

You can add more macOS preferences by adding new targets to the Makefile.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Credit

This README.md was _mostly_ generated via [Junie](https://www.jetbrains.com/junie/).