#!/bin/bash

set -o pipefail

PEX_BINARY=$(basename "$RD_CONFIG_PEX_SOURCE_URL")
WORKDIR=$(mktemp -d "$RD_PLUGIN_TMPDIR/pextmp.XXXXX")
SSH_KEY_STORAGE_PATH=$(mktemp "$WORKDIR/ssh-keyfile.XXXXX")
EXTRA_VARS_PATH=$(mktemp "$WORKDIR/extra-vars.XXXXX")
PEX_CACHE=$WORKDIR/.pex
ROLESDIR=${WORKDIR}/$(dirname "$RD_CONFIG_PLAYBOOK")/roles
extra_args=()
trap 'rm -rf $WORKDIR' EXIT


function ansible-galaxy () {
    if [[ -n "$RD_CONFIG_ANSIBLE_GALAXY_SOURCE" ]]; then
        echo "Downloading the ansible source code from ansible galaxy: $RD_CONFIG_ANSIBLE_GALAXY_SOURCE"
        if ! PEX_ROOT=${PEX_CACHE} PEX_SCRIPT=ansible-galaxy ./"$PEX_BINARY" \
            install \
            --role-file "$RD_CONFIG_ANSIBLE_GALAXY_SOURCE" \
            --roles-path "$ROLESDIR" \
            --ignore-certs
        then
            echo "Unable to download the ansible galaxy roles"; exit 1
        fi
    else
        echo "ansible-galaxy was selected but no source url provided."; exit 1
    fi
}

function tarfile () {
    if [[ -n "$RD_CONFIG_TARFILE_SOURCE" ]]; then
        echo "Downloading the ansible source code from a tar archive: $RD_CONFIG_TARFILE_SOURCE"
        if ! tar xvf "$(basename "$RD_CONFIG_TARFILE_SOURCE")"
        then
            echo "Unable to extract the tarfile"; exit 1
        fi
    else
        echo "tarfile was selected but no source url provided."; exit 1
    fi
}

function git-repo () {
    if [[ -n "$RD_CONFIG_GITREPO_SOURCE" ]]; then
        echo "Downloading the ansible source code from git repo: $RD_CONFIG_GITREPO_SOURCE"
        if ! git clone "$RD_CONFIG_GITREPO_SOURCE" > /dev/null 2>&1
        then
            echo "Failed to download from $RD_CONFIG_GITREPO_SOURCE repo"; exit 1
        fi
    else
        echo "git-repo was selected but no source url provided."; exit 1
    fi
}

cd "$WORKDIR" || exit

curl -fLOsS "$RD_CONFIG_PEX_SOURCE_URL" && echo "Ansible PEX downloaded successfully"
chmod +x "$PEX_BINARY"
echo "Running with below ansible version and settings:"
PEX_ROOT=${PEX_CACHE} PEX_SCRIPT=ansible ./"$PEX_BINARY" --version

if [[ -n "$RD_CONFIG_SOURCE_CODE_DOWNLOAD_OPTIONS" ]]; then
    IFS=',' read -r -a download_options <<< "$RD_CONFIG_SOURCE_CODE_DOWNLOAD_OPTIONS"
    for download_option in "${download_options[@]}"; do
        $download_option
    done
else
    echo "No download source provided"; exit 1
fi

echo "$RD_CONFIG_SSH_KEY_STORAGE_PATH" > "$SSH_KEY_STORAGE_PATH"
echo "$RD_CONFIG_EXTRA_VARS" | tr ',' '\n' > "$EXTRA_VARS_PATH"
sed -i 's/^ *//' "$EXTRA_VARS_PATH"

if [[ -n "$RD_CONFIG_EXTRA_VARS" ]]; then
    extra_args+=(--extra-vars=@"$EXTRA_VARS_PATH")
fi

if [[ -n "$RD_CONFIG_VAULT_FILE" ]]; then
    extra_args+=(--vault-password-file="$RD_CONFIG_VAULT_FILE")
fi

if [[ -n "$RD_CONFIG_EXTRA_RAW_CMDS" ]]; then
    for raw_cmd in $RD_CONFIG_EXTRA_RAW_CMDS; do
        extra_args+=("$raw_cmd")
    done
fi

if [[ $RD_CONFIG_BECOME == true ]]; then
    extra_args+=(--become)
fi

if [[ $RD_CONFIG_CHECK_MODE == true ]]; then
    extra_args+=(--check)
fi

if [[ -n "$RD_CONFIG_LIMIT" ]]; then
    extra_args+=(--limit="$RD_CONFIG_LIMIT")
fi

if ! PEX_ROOT=${PEX_CACHE} PEX_SCRIPT=ansible-playbook ./"$PEX_BINARY" \
    "$RD_CONFIG_PLAYBOOK" \
    --user="$RD_CONFIG_ANSIBLE_USER" \
    --private-key="$SSH_KEY_STORAGE_PATH" \
    --inventory="$RD_CONFIG_INVENTORY_FILE" \
    --ssh-extra-args='-o StrictHostKeyChecking=no' \
    "${extra_args[@]}"
then
    exit 1
fi


