#!/usr/bin/env bash

if [[ ! "$#" -gt 2 ]]; then
    echo "Missing id or package or dir name" >&2
    exit 2
fi

for env_var in ADDON_VERSION ADDON_OVERLAY; do
  if [ -z "${!env_var}" ]; then
    echo "Make sure to set the ${env_var} environment variable." >&2
    exit 2
  fi
done

export BUNDLE_BASE=$(dirname "${BASH_SOURCE[0]}")/..
export BUNDLE_ID="${1}"
export BUNDLE_NAME="${2}"
export BUNDLE_DIR="${3}"
export BUNDLE_CHANNEL="${4}"
export DIR_OVERLAY="${BUNDLE_BASE}/kustomize/overlays/${ADDON_OVERLAY}/data-plane/${BUNDLE_ID}"
export DIR_ADDON="${BUNDLE_BASE}/addons/connectors-operator/${BUNDLE_DIR}"

if [ ! -d "${DIR_OVERLAY}" ]; then
    echo "Missing overlay ${DIR_OVERLAY}" >&2
    exit 2
fi

function bundle_external_operators() {
  local kustomization=$1
  local container_image=''
  local version=''

  container_image=$(printf '%s\n' "$kustomization" | yq 'select(.kind=="Deployment").spec.template.spec.containers[0].image')
  version=$(printf '%s' "$container_image" | cut -f 2 -d ':' | tr '[:upper:]' '[:lower:]')
  version=${version:0:25}
  container_image_name=$(printf '%s' "$container_image" | cut -f 1 -d ':')
  container_image_sha256=$(skopeo inspect "docker://$container_image" --format "{{.Digest}}")

  DIR_ADDON="${DIR_ADDON}/${version}"

  printf '%s\n' "$kustomization" | operator-sdk generate bundle \
    --package "${BUNDLE_NAME}" \
    --channels "${BUNDLE_CHANNEL}" \
    --default-channel "${BUNDLE_CHANNEL}" \
    --output-dir "${DIR_ADDON}" \
    --version "${version}" \
    --kustomize-dir "${DIR_OVERLAY}"
    
    container_image_new_name="$container_image_name@$container_image_sha256" \
    yq -i \
    '.spec.install.spec.deployments[0].spec.template.spec.containers[0].image=strenv(container_image_new_name)'\
     "${DIR_ADDON}/manifests/${BUNDLE_NAME}.clusterserviceversion.yaml"

    yq -i 'del(.spec.install.spec.deployments[].label)' \
    "${DIR_ADDON}/manifests/${BUNDLE_NAME}.clusterserviceversion.yaml"
}

function bundle() {
  local kustomization=$1
  printf '%s\n' "$kustomization" | operator-sdk generate bundle \
    --package "${BUNDLE_NAME}" \
    --channels "${BUNDLE_CHANNEL}" \
    --default-channel "${BUNDLE_CHANNEL}" \
    --output-dir "${DIR_ADDON}" \
    --version "${ADDON_VERSION}" \
    --kustomize-dir "${DIR_OVERLAY}"
}

function main() {
  echo "##############################################"
  echo "# id      : ${BUNDLE_ID}"
  echo "# version : ${ADDON_VERSION}"
  echo "# dir     : ${BUNDLE_DIR}"
  echo "# package : ${BUNDLE_NAME}"
  echo "# base    : ${BUNDLE_BASE}"
  echo "# channel : ${BUNDLE_CHANNEL}"
  echo "##############################################"

  kustomization=$(kustomize build "${DIR_OVERLAY}")

  if [[ "${BUNDLE_ID}" = "strimzi"* ]] || [[ "${BUNDLE_ID}" = "camel-k"* ]]; then
    bundle_external_operators "$kustomization"
  else
    bundle "$kustomization"
  fi

  rm bundle.Dockerfile

  yq -i 'del(.annotations."operators.operatorframework.io.metrics.builder")
        | del(.annotations."operators.operatorframework.io.metrics.mediatype.v1")
        | del(.annotations."operators.operatorframework.io.metrics.project_layout")
        | del(.annotations."operators.operatorframework.io.test.mediatype.v1")
        | del(.annotations."operators.operatorframework.io.test.config.v1")
        ' \
    "${DIR_ADDON}/metadata/annotations.yaml"


  yq -i 'del(.metadata.annotations."operators.operatorframework.io/builder")
        | del(.metadata.annotations."operators.operatorframework.io/project_layout")
        | del(.spec.icon[0])
        ' \
    "${DIR_ADDON}/manifests/${BUNDLE_NAME}.clusterserviceversion.yaml"
}

main "@"
