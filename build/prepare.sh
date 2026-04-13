#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
PACKAGE_DIR="${ROOT_DIR}/package"
MANIFEST_FILE="${PACKAGE_DIR}/manifest.yml"
ENV_FILE="${ROOT_DIR}/project.env"

RABBITMQ_BRANCH="${1}"
RABBITMQ_BASE_VERSION="$(echo ${RABBITMQ_BRANCH} | cut -d'.' -f1,2)"

echo "Setting up PauseR build for ${RABBITMQ_BRANCH} (base version ${RABBITMQ_BASE_VERSION})"

YQ_OPTS="-i"
if yq --version 2>&1 | grep -qi 'mikefarah'; then
  # mikefarah/yq (common on macOS Homebrew)
  yq -i "
    .rabbitmq.min = \"${RABBITMQ_BASE_VERSION}\" |
    .rabbitmq.max = \"${RABBITMQ_BRANCH}\"
  " "$MANIFEST_FILE"
else
  yq -y -i "
    .rabbitmq.min = \"${RABBITMQ_BASE_VERSION}\" |
    .rabbitmq.max = \"${RABBITMQ_BRANCH}\"
  " "$MANIFEST_FILE"
fi

echo RABBITMQ_BASE="${RABBITMQ_BRANCH}" >> "${ENV_FILE}"