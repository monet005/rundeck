#!/bin/bash

set -eo pipefail

TMPDIR=/jboss/support/dump
WORKDIR=$(mktemp -d "$TMPDIR/pextmp.XXXXX")
BBDIR=$(mktemp -d "$TMPDIR/pextmpbb.XXXXX")
PEX_CACHE=${WORKDIR}/.pex
ROLESDIR=${WORKDIR}/$(dirname "$RD_CONFIG_PLAYBOOK")/roles
PLUGIN_VERSION=${RD_CONFIG_PLUGIN_VERSION//## /}
PEX_YAML_NAME=sabre_ansible_config.yaml
PEX_YAML_FILEPATH=${WORKDIR}/$PEX_YAML_NAME
PEX_YAML_VARNAME=pex_url
extra_args=()
trap 'rm -rf $WORKDIR $BBDIR' EXIT

function logit () {
    case "$1" in
        fatal) echo "EXITING : $2"; exit 1 ;;
        info) echo "INFO : $2" ;;
    esac
}

function check_path () {
    if [[ ! -f $1 ]]; then
        logit fatal "$1 path does not exists"
    fi
}

function ansible_galaxy_download () {
    if [[ -n "$RD_CONFIG_ANSIBLE_GALAXY_SOURCE" ]]; then
        logit info "Downloading the ansible source code from ansible galaxy: $RD_CONFIG_ANSIBLE_GALAXY_SOURCE"
        if ! PEX_ROOT=${PEX_CACHE} PEX_SCRIPT=ansible-galaxy ./"$ANSIBLE_PEX_BINARY" \
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

function package_download () {
    if [[ -n "$RD_CONFIG_PACKAGE_SOURCE" ]]; then
        logit info "Downloading the ansible source code from a package: $RD_CONFIG_PACKAGE_SOURCE"
        if ! curl -fLOsS "$RD_CONFIG_PACKAGE_SOURCE"
        then
            logit fatal "Unable to download the package"
        fi
        if ! tar xvf "$(basename "$RD_CONFIG_PACKAGE_SOURCE")"
        then
            logit fatal "Unable to extract the package"
        fi
    else
        logit fatal "package was selected but no source url provided"
    fi
}

function bitbucket_download () {
    if [[ -n "$RD_CONFIG_BITBUCKET_SOURCE" ]]; then
        case "$RD_CONFIG_BITBUCKET_CLONE_METHOD" in
            ssh_with_key_from_keystore) 
                BITBUCKET_SSH_KEY_STORAGE_PATH=$(mktemp "$BBDIR/bitbucket-ssh-keyfile.XXXXX")
                echo "$RD_CONFIG_BITBUCKET_SSH_KEY_FROM_KEYSTORE" > "$BITBUCKET_SSH_KEY_STORAGE_PATH"
                logit info "Downloading from $RD_CONFIG_BITBUCKET_SOURCE via ssh"
                GIT_SSH_COMMAND="ssh -i $BITBUCKET_SSH_KEY_STORAGE_PATH -o StrictHostKeyChecking=no" git clone "$RD_CONFIG_BITBUCKET_SOURCE" . > /dev/null 2>&1
                if [[ $? -ne 0 ]]; then
                    logit fatal "Failed to download from $RD_CONFIG_BITBUCKET_SOURCE repo"
                fi
                ;;
            ssh_with_key_from_a_file)
                BITBUCKET_SSH_KEY_STORAGE_PATH=$(mktemp "$BBDIR/bitbucket-ssh-keyfile.XXXXX")
                check_path "$RD_CONFIG_BITBUCKET_SSH_KEY_FROM_A_FILE"
                if ! cp "$RD_CONFIG_BITBUCKET_SSH_KEY_FROM_A_FILE" "$BITBUCKET_SSH_KEY_STORAGE_PATH"
                then
                    logit fatal "Unable to access the local ssh private key path $RD_CONFIG_BITBUCKET_SSH_KEY_FROM_A_FILE"
                fi
                if ! chmod 600 "$BITBUCKET_SSH_KEY_STORAGE_PATH"
                then
                    logit fatal "Unable to set the correct permission for a private key"
                fi
                logit info "Downloading from $RD_CONFIG_BITBUCKET_SOURCE via ssh"
                GIT_SSH_COMMAND="ssh -i $BITBUCKET_SSH_KEY_STORAGE_PATH -o StrictHostKeyChecking=no" git clone "$RD_CONFIG_BITBUCKET_SOURCE" . > /dev/null 2>&1
                if [[ $? -ne 0 ]]; then
                    logit fatal "Failed to download from $RD_CONFIG_BITBUCKET_SOURCE repo"
                fi
                ;;
            https)
                logit info "Downloading from source code via https"
                if ! git clone "$RD_CONFIG_BITBUCKET_SOURCE" . > /dev/null 2>&1
                then
                    logit fatal "Failed to download from $RD_CONFIG_BITBUCKET_SOURCE repo"
                fi
                ;;
            *) logit fatal "Selected clone method is not supported"
                ;;
        esac
    else
        logit fatal "bitbucket was selected but no source url provided"
    fi
}

function get_ansible_pex () {
    if [[ ! -f "$PEX_YAML_FILEPATH" ]]; then
        logit fatal "$PEX_YAML_FILEPATH does not exist in the repo"
    else
        if ! grep -q ^$PEX_YAML_VARNAME "$PEX_YAML_FILEPATH"
        then
            logit fatal "The defined ansible pex url key in $PEX_YAML_NAME is not set to $PEX_YAML_VARNAME"
        else
            ANSIBLE_PEX_SRC=$(sed -n "s/^$PEX_YAML_VARNAME:.*\(http[s]\?:\/\/\S*\)/\1/p" "$PEX_YAML_FILEPATH")
            ANSIBLE_PEX_BINARY=$(basename "$ANSIBLE_PEX_SRC")
            logit info "Downloading the ansible pex version defined in $PEX_YAML_FILEPATH"
            if ! curl -fLOsS "$ANSIBLE_PEX_SRC"
            then
                logit fatal "Unable to download ansible pex from $ANSIBLE_PEX_SRC"
            fi
            chmod +x "$ANSIBLE_PEX_BINARY"
        fi
    fi 
}


######################################
# Main

logit info "Plugin Version $PLUGIN_VERSION"

cd "$WORKDIR" || exit

case "$RD_CONFIG_SOURCE_CODE_DOWNLOAD_OPTIONS" in
    bitbucket) bitbucket_download;;
    package) package_download;;
esac

# Perform git operations here when commit id is specified
if [[ -n "$RD_CONFIG_GIT_COMMIT_ID" ]]; then
    logit info "Checking out $RD_CONFIG_GIT_COMMIT_ID"
    if ! git --git-dir "$WORKDIR/.git" --work-tree "$WORKDIR" checkout "$RD_CONFIG_GIT_COMMIT_ID"
    then
        logit fatal "The provided Git Branch/Tag/Commit ID $RD_CONFIG_GIT_COMMIT_ID is invalid"
    fi
fi

if [[ $RD_CONFIG_GIT_SUBMODULE == true ]]; then
    logit info "Running git submodule update"
    if ! git submodule update --init --recursive
    then
        logit fatal "Git submodule update failed"
    fi
fi

get_ansible_pex

if [[ -n "$RD_CONFIG_ANSIBLE_GALAXY_SOURCE" ]]; then
    check_path "$RD_CONFIG_ANSIBLE_GALAXY_SOURCE"
    ansible_galaxy_download
fi

SSH_KEY_STORAGE_PATH=$(mktemp "$WORKDIR/ssh-keyfile.XXXXX")
EXTRA_VARS_PATH=$(mktemp "$WORKDIR/extra-vars.XXXXX")

echo "$RD_CONFIG_SSH_KEY_STORAGE_PATH" > "$SSH_KEY_STORAGE_PATH"

if [[ -n "$RD_CONFIG_EXTRA_VARS" ]]; then
    echo "$RD_CONFIG_EXTRA_VARS" > "$EXTRA_VARS_PATH"
    extra_args+=(--extra-vars=@"$EXTRA_VARS_PATH")
fi

if [[ -n "$RD_CONFIG_VAULT_FILE" ]]; then
    check_path "$RD_CONFIG_VAULT_FILE"
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

# Check if the provided inventory file exists in the repo
check_path "$RD_CONFIG_INVENTORY_FILE"

logit info "Running with below ansible version and settings:"
PEX_ROOT=${PEX_CACHE} PEX_SCRIPT=ansible ./"$ANSIBLE_PEX_BINARY" --version

# To enable ansible fact caching from the provided inventory file.
if [[ "$RD_CONFIG_ANSIBLE_FACTS_CACHE" == true ]]; then
    logit info "Ansible facts cache is enabled, running the command: ansible -m setup -i $RD_CONFIG_INVENTORY_FILE all"
    if ! PEX_ROOT=${PEX_CACHE} PEX_SCRIPT=ansible ./"$ANSIBLE_PEX_BINARY" all \
    --inventory="$RD_CONFIG_INVENTORY_FILE" \
    --module-name setup \
    --user="$RD_CONFIG_ANSIBLE_USER" \
    --ssh-extra-args='-o StrictHostKeyChecking=no' \
    --private-key="$SSH_KEY_STORAGE_PATH" \
    --extra-vars ansible_user="$RD_CONFIG_ANSIBLE_USER" > /dev/null 2>&1
    then
        logit fatal "Ansible facts gathering failed"
    fi
fi

logit info "Executing $RD_CONFIG_PLAYBOOK playbook with these extra command arguments: \
--user=$RD_CONFIG_ANSIBLE_USER --inventory=$RD_CONFIG_INVENTORY_FILE ${extra_args[*]}"

if ! PEX_ROOT=${PEX_CACHE} PEX_SCRIPT=ansible-playbook ./"$ANSIBLE_PEX_BINARY" \
    "$RD_CONFIG_PLAYBOOK" \
    --user="$RD_CONFIG_ANSIBLE_USER" \
    --private-key="$SSH_KEY_STORAGE_PATH" \
    --inventory="$RD_CONFIG_INVENTORY_FILE" \
    --ssh-extra-args='-o StrictHostKeyChecking=no' \
    --diff \
    "${extra_args[@]}"
then
    logit fatal "$RD_CONFIG_PLAYBOOK playbook execution is not successful"
fi
