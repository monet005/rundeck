#!/bin/bash

set -o pipefail

PEX_BINARY=$(basename "$RD_CONFIG_PEX_SOURCE_URL")
TMPDIR=$RD_PLUGIN_TMPDIR/pextmp
PEX_CACHE=$RD_CONFIG_WORKDIR/.pex
extra_args=()

cd "$RD_CONFIG_WORKDIR" || exit
curl -fLOsS "$RD_CONFIG_PEX_SOURCE_URL" && echo "Ansible PEX downloaded successfully"
chmod +x "$PEX_BINARY"
echo "Running with below ansible version and settings:"
PEX_ROOT=${PEX_CACHE} PEX_SCRIPT=ansible ./"$PEX_BINARY" --version

mkdir -p "$TMPDIR"
SSH_KEY_STORAGE_PATH=$(mktemp "$TMPDIR/ssh-keyfile.XXXXX")
EXTRA_VARS_PATH=$(mktemp "$TMPDIR/extra-vars.XXXXX")
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

trap 'rm -rf $TMPDIR' EXIT

echo "${extra_args[@]}"

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


