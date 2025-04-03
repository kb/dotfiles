.PHONY: stow install-homebrew brew-stow brew-bundle install-oh-my-zsh mac-prefs

# Fixed paths for Apple Silicon/ARM
BREW := /opt/homebrew/bin/brew
STOW := /opt/homebrew/bin/stow

setup: install-homebrew brew-stow stow brew-bundle install-oh-my-zsh mac-prefs

install-homebrew:
	@[ -f $(BREW) ] || /bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

install-oh-my-zsh:
	@[ -d "$(HOME)/.oh-my-zsh" ] || sh -c "$$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

brew-stow:
	@$(BREW) list stow &>/dev/null || $(BREW) install stow

brew-bundle: stow-homebrew
	@$(BREW) bundle --file homebrew/Brewfile

stow: stow-scripts stow-zsh stow-ssh stow-git stow-1pw stow-homebrew stow-emacs
	@echo "All dotfiles have been stowed"

stow-zsh:
	@if [ -f $(HOME)/.zshrc ]; then \
		DOTFILE_SHA=$$(sha256sum $(PWD)/zsh/dot-zshrc 2>/dev/null | cut -d' ' -f1); \
		EXISTING_SHA=$$(sha256sum $(HOME)/.zshrc 2>/dev/null | cut -d' ' -f1); \
		if [ "$$DOTFILE_SHA" != "$$EXISTING_SHA" ]; then \
			echo "Existing .zshrc differs from dotfiles version, backing up to $(HOME)/.zshrc.backup-$$(date +%Y%m%d%H%M%S)"; \
			mv $(HOME)/.zshrc $(HOME)/.zshrc.backup-$$(date +%Y%m%d%H%M%S); \
		fi; \
	fi
	$(STOW) zsh --dotfiles

stow-ssh:
	$(STOW) ssh --no-folding

stow-git:
	$(STOW) git --dotfiles

stow-1pw:
	$(STOW) 1password --no-folding

stow-homebrew:
	$(STOW) homebrew

stow-emacs:
	$(STOW) emacs --dotfiles

stow-scripts:
	$(STOW) scripts --dotfiles

mac-prefs: show-extensions disable-natural-scroll hide-dock remap-caps-to-ctrl
	@echo "Mac preferences have been set"

show-extensions:
	@echo "Setting to show filename extensions by default"
	@defaults write NSGlobalDomain AppleShowAllExtensions -bool true

disable-natural-scroll:
	@echo "Disabling natural scroll"
	@defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false

hide-dock:
	@echo "Setting Dock to auto-hide"
	@defaults write com.apple.dock autohide -bool true
	@killall Dock

remap-caps-to-ctrl:
	@echo "Remapping Caps Lock to Control key"
	@hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000E0}]}'
