#!/bin/bash

set -eo pipefail

PEX_BINARY=$(basename "$RD_CONFIG_PEX_SOURCE_URL")
WORKDIR=$(mktemp -d "$RD_PLUGIN_TMPDIR/pextmp.XXXXX")
SSH_KEY_STORAGE_PATH=$(mktemp "$WORKDIR/ssh-keyfile.XXXXX")
EXTRA_VARS_PATH=$(mktemp "$WORKDIR/extra-vars.XXXXX")
PEX_CACHE=$WORKDIR/.pex
ROLESDIR=${WORKDIR}/$(dirname "$RD_CONFIG_PLAYBOOK")/roles
REPODIR=${WORKDIR}/$(dirname "$RD_CONFIG_PLAYBOOK" | cut -d/ -f1)
extra_args=()
PLUGIN_VERSION=${RD_CONFIG_PLUGIN_VERSION//## /}
trap 'rm -rf $WORKDIR' EXIT

function logit () {
    case "$1" in
        fatal) echo "EXITING : $2"; exit 1 ;;
        info) echo "INFO : $2" ;;
    esac
}

function ansible-galaxy () {
    if [[ -n "$RD_CONFIG_ANSIBLE_GALAXY_SOURCE" ]]; then
        logit info "Downloading the ansible source code from ansible galaxy: $RD_CONFIG_ANSIBLE_GALAXY_SOURCE"
        if ! PEX_ROOT=${PEX_CACHE} PEX_SCRIPT=ansible-galaxy ./"$PEX_BINARY" \
            install \
            --role-file "$RD_CONFIG_ANSIBLE_GALAXY_SOURCE" \
            --roles-path "$ROLESDIR" \
            --ignore-certs
        then
            logit fatal "Unable to download the ansible galaxy roles"
        fi
    else
        logit fatal "ansible-galaxy was selected but no source url provided"
    fi
}

function tarfile () {
    if [[ -n "$RD_CONFIG_TARFILE_SOURCE" ]]; then
        logit info "Downloading the ansible source code from a tar archive: $RD_CONFIG_TARFILE_SOURCE"
        if ! curl -fLOsS "$RD_CONFIG_TARFILE_SOURCE"
        then
            logit fatal "Unable to download the tarfile"
        fi
        if ! tar xvf "$(basename "$RD_CONFIG_TARFILE_SOURCE")"
        then
            logit fatal "Unable to extract the tarfile"
        fi
    else
        logit fatal "tarfile was selected but no source url provided"
    fi
}

function git-repo () {
    if [[ -n "$RD_CONFIG_GITREPO_SOURCE" ]]; then
        logit info "Downloading the ansible source code from git repo: $RD_CONFIG_GITREPO_SOURCE"
        if ! git clone "$RD_CONFIG_GITREPO_SOURCE" > /dev/null 2>&1
        then
            logit fatal "Failed to download from $RD_CONFIG_GITREPO_SOURCE repo"
        fi
    else
        logit fatal "git-repo was selected but no source url provided"
    fi
}

logit info "Plugin Version $PLUGIN_VERSION"

cd "$WORKDIR" || exit

curl -fLOsS "$RD_CONFIG_PEX_SOURCE_URL" && logit info "Ansible PEX downloaded successfully"
chmod +x "$PEX_BINARY"
logit info "Running with below ansible version and settings:"
PEX_ROOT=${PEX_CACHE} PEX_SCRIPT=ansible ./"$PEX_BINARY" --version

if [[ -n "$RD_CONFIG_SOURCE_CODE_DOWNLOAD_OPTIONS" ]]; then
    IFS=',' read -r -a download_options <<< "$RD_CONFIG_SOURCE_CODE_DOWNLOAD_OPTIONS"
    for download_option in "${download_options[@]}"; do
        $download_option
    done
else
    logit fatal "No download source provided"; exit 1
fi

echo "$RD_CONFIG_SSH_KEY_STORAGE_PATH" > "$SSH_KEY_STORAGE_PATH"

if [[ -n "$RD_CONFIG_EXTRA_VARS" ]]; then
    echo "$RD_CONFIG_EXTRA_VARS" | tr ',' '\n' > "$EXTRA_VARS_PATH"
    sed -i 's/^ *//' "$EXTRA_VARS_PATH"
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

if [[ -n "$RD_CONFIG_GIT_COMMIT_ID" ]]; then
    logit info "Checking out $RD_CONFIG_GIT_COMMIT_ID commit ID"
    if ! git --git-dir "$REPODIR/.git" --work-tree "$REPODIR" checkout "$RD_CONFIG_GIT_COMMIT_ID"
    then
        logit fatal "The provided commit ID $RD_CONFIG_GIT_COMMIT_ID is invalid"
    fi
fi

logit info "Executing ansible-playbook with these extra command arguments: ${extra_args[*]}"

if ! PEX_ROOT=${PEX_CACHE} PEX_SCRIPT=ansible-playbook ./"$PEX_BINARY" \
    "$RD_CONFIG_PLAYBOOK" \
    --user="$RD_CONFIG_ANSIBLE_USER" \
    --private-key="$SSH_KEY_STORAGE_PATH" \
    --inventory="$RD_CONFIG_INVENTORY_FILE" \
    --ssh-extra-args='-o StrictHostKeyChecking=no' \
    "${extra_args[@]}"
then
    logit fatal "$RD_CONFIG_PLAYBOOK playbook execution is not successful"
fi


