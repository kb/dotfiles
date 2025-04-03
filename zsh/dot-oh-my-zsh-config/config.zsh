# You can put files here to add functionality separated per file, which
# will be ignored by git.
# Files on the custom/ directory will be automatically loaded by the init
# script, in alphabetical order.

# For example: add yourself some shortcuts to projects you often work on.
#
# brainstormr=~/Projects/development/planetargon/brainstormr
# cd $brainstormr

# Get path setup before attempting to run executables
path+=("${HOME}/.scripts")
path+=("${HOME}/.rbenv/bin")
path+=("${HOME}/go/bin")
path+=("${DIGITS_REPO_PATH}/development/bin")

# Digits specific env vars
export DIGITS_REPO_PATH="${HOME}/Developer"
export GCP_ACCOUNT_EMAIL="kyle@digits.com"

# make brew available
eval "$(/opt/homebrew/bin/brew shellenv)"

# Source the function before the export below
source keychain-environment-variables

# AWS configuration example, after doing:
# $  set-keychain-environment-variable AWS_ACCESS_KEY_ID
#       provide: "AKIAYOURACCESSKEY"
# $  set-keychain-environment-variable AWS_SECRET_ACCESS_KEY
#       provide: "j1/yoursupersecret/password"
# 1password service account token to access dotfiles vault
export OP_SERVICE_ACCOUNT_TOKEN=$(keychain-environment-variable OP_SERVICE_ACCOUNT_TOKEN);

export SECRETS_DIR="${ZSH_CUSTOM}/secrets"
##### Dotfiles secrets management start #####
# Define the secrets output path variable which is missing
secrets_out_path="${SECRETS_DIR}/secrets-out.zsh"

if [ ! -f "$secrets_out_path" ]; then
    # Only show message when file doesn't exist
    echo "Creating ${secrets_out_path}..."
    op inject --in-file "${SECRETS_DIR}/secrets-in.zsh" --out-file "$secrets_out_path"
else
    # Check if secrets need updating, but do so silently
    secrets_in_no_values=$(cat "${SECRETS_DIR}/secrets-in.zsh" | sed 's/=.*//' | base64)
    secrets_out_no_values=$(cat "$secrets_out_path" | sed 's/=.*//' | base64)

    if [ ! "$secrets_in_no_values" = "$secrets_out_no_values" ]; then
        # Only show message when update is needed
        echo "Secrets have changed... Updating ${secrets_out_path}"
        rm "$secrets_out_path"
        op inject --in-file "${SECRETS_DIR}/secrets-in.zsh" --out-file "$secrets_out_path"
    fi
fi

source "$secrets_out_path"
###### Dotfiles secrets management end #####

# gcloud
source "/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc"
export USE_GKE_GCLOUD_AUTH_PLUGIN=True

# rbenv
eval "$(rbenv init - zsh)"

# pyenv
eval "$(pyenv init - zsh)"

# Select the appropriate JAVA_HOME only if the java version is available
JAVA_HOME_OUTPUT=$(/usr/libexec/java_home -v21 2>/dev/null)

if [ -n "$JAVA_HOME_OUTPUT" ]; then
  export JAVA_HOME="$JAVA_HOME_OUTPUT"
else
  echo "Warning: Java version 21 is not installed. JAVA_HOME is not set."
fi
