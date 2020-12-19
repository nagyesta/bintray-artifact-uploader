#!/bin/sh -l

printf "\n"
printf "       ::  ██████╗         █████╗        ██╗   ██╗     ::\n"
printf "       ::  ██╔══██╗       ██╔══██╗       ██║   ██║     ::\n"
printf "       ::  ██████╔╝       ███████║       ██║   ██║     ::\n"
printf "       ::  ██╔══██╗       ██╔══██║       ██║   ██║     ::\n"
printf "       ::  ██████╔╝██╗    ██║  ██║██╗    ╚██████╔╝██╗  ::\n"
printf "       ::  ╚═════╝ ╚═╝    ╚═╝  ╚═╝╚═╝     ╚═════╝ ╚═╝  ::\n"
printf "\n"
printf "       :: Starting up...\n"
printf "\n"

cd /github/workspace/ || exit

export ENABLED_LOG_LEVEL_DEBUG=${INPUT_DEBUG_LOG:-false}
export ENABLED_LOG_LEVEL_INFO=${INPUT_DEBUG_LOG:-true}
export ENABLED_LOG_LEVEL_WARN=${INPUT_DEBUG_LOG:-true}
export ENABLED_LOG_LEVEL_ERROR=${INPUT_DEBUG_LOG:-true}

# Define validation steps

get_value_of() {
  VARIABLE_NAME=$1
  VARIABLE_VALUE=""
  if set | grep -q "^$VARIABLE_NAME="; then
    eval VARIABLE_VALUE="\$$VARIABLE_NAME"
  fi
  printf "%s" "${VARIABLE_VALUE}"
}

log() {
  LOG_LEVEL="$1"
  if [ "$(get_value_of "ENABLED_LOG_LEVEL_${LOG_LEVEL}")" = "true" ] ; then
    printf "%6s :: %s\n" "${LOG_LEVEL}" "$2"
  fi
}

validate_input() {
  VARIABLE_NAME="INPUT_$1"
  VARIABLE_VALUE=$(get_value_of "${VARIABLE_NAME}")
  if [ -z "${VARIABLE_VALUE}" ]; then
    log "ERROR" "$(printf "%s is not set" "${VARIABLE_NAME}")"
    exit 1
  fi
}

# Validate mandatory input

validate_input "POM_FILE_NAME"
validate_input "ARTIFACT_GROUP_ID"
validate_input "ARTIFACT_ARTIFACT_ID"
validate_input "API_USER"
validate_input "API_KEY"
validate_input "REPO"
validate_input "PACKAGE_NAME"

# Transform input to easier to use format

export DRY_RUN_ONLY="${INPUT_DRY_RUN:-false}"
export BINTRAY_VERSION_PREFIX="${INPUT_BINTRAY_VERSION_PREFIX:-v}"
export BINTRAY_ART_GROUP="${INPUT_ARTIFACT_GROUP_ID}"
export BINTRAY_ART_NAME="${INPUT_ARTIFACT_ARTIFACT_ID}"
if [ -z "${INPUT_ARTIFACT_VERSION}" ]; then
  BINTRAY_ART_VERSION=$(git log --format='format:%d' --decorate-refs="refs/tags/${BINTRAY_VERSION_PREFIX}*" -n 1 | grep tag: | sed 's/^.*tag: //' | sed "s/${BINTRAY_VERSION_PREFIX}//" | sed 's/[,)].*$//')
  if [ -z "${BINTRAY_ART_VERSION}" ] ; then
    log "ERROR" "INPUT_ARTIFACT_VERSION was not set and no matching tag was found."
    exit 2
  fi
  export BINTRAY_ART_VERSION
else
  export BINTRAY_ART_VERSION="${INPUT_ARTIFACT_VERSION}"
fi

export BINTRAY_API_USER="${INPUT_API_USER}"
export BINTRAY_API_KEY="${INPUT_API_KEY}"
export BINTRAY_REPO="${INPUT_REPO}"
BINTRAY_SUBJECT=$([ -n "${INPUT_SUBJECT}" ] && printf "%s" "${INPUT_SUBJECT}" || printf "%s" "${BINTRAY_API_USER}")
export BINTRAY_SUBJECT
export BINTRAY_PACKAGE="${INPUT_PACKAGE_NAME}"
export BINTRAY_VERSION="${BINTRAY_VERSION_PREFIX}${BINTRAY_ART_VERSION}"
BINTRAY_PATH=$(echo "${BINTRAY_ART_GROUP}" | sed s/\\./\\//g)
export BINTRAY_PATH

export BINTRAY_BASE_URL=${INPUT_BASE_URL:-https://api.bintray.com/}

if ! echo "${BINTRAY_BASE_URL}" | grep "^http.\\+" >/dev/null 2>&1; then
  log "ERROR" "$(printf "INPUT_BASE_URL must start with 'http' and end with a '/'")"
  exit 1
fi

if ! echo "${BINTRAY_BASE_URL}" | grep "^http.\\+/$" >/dev/null 2>&1; then
  export BINTRAY_BASE_URL="${BINTRAY_BASE_URL}/"
fi

# Define upload functions

create_version_if_missing() {
  BINTRAY_VERSION_URL="${BINTRAY_BASE_URL}packages/${BINTRAY_SUBJECT}/${BINTRAY_REPO}/${BINTRAY_PACKAGE}/versions/${BINTRAY_VERSION}"
  log "DEBUG" "$(printf "Sending GET to %s" "${BINTRAY_VERSION_URL}")"
  if ! curl -s -o /home/curl_user/version_response.txt "-u${BINTRAY_API_USER}:${BINTRAY_API_KEY}" "${BINTRAY_VERSION_URL}"; then
    printf "\n"
    log "ERROR" "$(printf "The curl command failed.")"
    exit 5
  fi
  printf "\n"

  echo "{\"name\":\"${BINTRAY_VERSION}\",\"released\": \"$(date -Idate)T00:00:00.000Z\",\"desc\": \"\",\"vcs_tag\": \"${BINTRAY_VERSION}\"}" >/home/curl_user/vcreate.txt
  if grep </home/curl_user/version_response.txt "was not found" >/dev/null 2>&1; then
    log "INFO" "$(printf "Version not found: %s. Attempting to create it..." "${BINTRAY_VERSION}")"
    if ! curl -s -o /dev/null "-u${BINTRAY_API_USER}:${BINTRAY_API_KEY}" "${BINTRAY_BASE_URL}packages/${BINTRAY_SUBJECT}/${BINTRAY_REPO}/${BINTRAY_PACKAGE}/versions" -d "$(cat /home/curl_user/vcreate.txt)"; then
      printf "\n"
      log "ERROR" "$(printf "The curl command failed.")"
      exit 10
    else
      log "INFO" "Version created."
    fi
  else
    log "INFO" "$(printf "Version found: %s. OK." "${BINTRAY_VERSION}")"
  fi
}

upload_file() {
  LOCAL_FILE="$1"
  BINTRAY_URL="$2"
  ART_CLASSIFIER="$3"
  ART_PACKAGING="$4"
  printf "\n"
  log "INFO" "$(printf "Uploading %s" "${LOCAL_FILE}")"
  log "DEBUG" " to"
  log "DEBUG" "$(printf "  %s" "${BINTRAY_URL}")"
  log "DEBUG" " as artifact"
  log "DEBUG" "$(printf "  group: %s" "${BINTRAY_ART_GROUP}")"
  log "DEBUG" "$(printf "  name: %s" "${BINTRAY_ART_NAME}")"
  log "DEBUG" "$(printf "  version: %s" "${BINTRAY_ART_VERSION}")"
  log "DEBUG" "$(printf "  classifier: %s" "${ART_CLASSIFIER}")"
  log "DEBUG" "$(printf "  packaging: %s" "${ART_PACKAGING}")"
  if [ "${DRY_RUN_ONLY}" = "false" ]; then
    rm -f response.txt
    if ! curl -s -T "${LOCAL_FILE}" -o /home/curl_user/response.txt "-u${BINTRAY_API_USER}:${BINTRAY_API_KEY}" -H "X-Bintray-Package:${BINTRAY_PACKAGE}" -H "X-Bintray-Version:${BINTRAY_VERSION}" "${BINTRAY_URL}"; then
      printf "\n"
      log "ERROR" "$(printf "The curl command failed.")"
      exit 20
    fi
    if ! grep </home/curl_user/response.txt '{"message":"success"}' >/dev/null 2>&1; then
      log "ERROR" "Unexpected response:"
      log "ERROR" "$(cat /home/curl_user/response.txt)"
      printf "\n"
      log "ERROR" "Exiting..."
      exit 30
    fi
    log "INFO" "Upload done."
  else
    log "INFO" "SIMULATION:"
    log "INFO" "$(printf "curl -T %s" "${LOCAL_FILE}")"
    log "INFO" "$(printf " -u%s:<API_KEY>" "${BINTRAY_API_USER}")"
    log "INFO" "$(printf " -H \"X-Bintray-Package:%s\"" "${BINTRAY_PACKAGE}")"
    log "INFO" "$(printf " -H \"X-Bintray-Version:%s\"" "${BINTRAY_VERSION}")"
    log "INFO" "$(printf " %s" "${BINTRAY_URL}")"
  fi
}

# Start execution

create_version_if_missing

BINTRAY_CONTENT_PATH="content/${BINTRAY_SUBJECT}/${BINTRAY_REPO}/${BINTRAY_PATH}/${BINTRAY_ART_NAME}/${BINTRAY_ART_VERSION}"

# POM

LOCAL_POM_FILE="/github/workspace/${INPUT_POM_FILE_NAME}"
if [ -n "${LOCAL_POM_FILE}" ] && [ -f "${LOCAL_POM_FILE}" ]; then
  BINTRAY_POM_URL="${BINTRAY_BASE_URL}${BINTRAY_CONTENT_PATH}/${BINTRAY_ART_NAME}-${BINTRAY_ART_VERSION}.pom"
  upload_file "${LOCAL_POM_FILE}" "${BINTRAY_POM_URL}" "-" "pom"
else
  printf "\n"
  log "INFO" "$(printf "SKIP POM: %s" "${LOCAL_POM_FILE:-NULL}")"
fi

# JAR

LOCAL_JAR_FILE="/github/workspace/${INPUT_JAR_FILE_NAME}"
if [ -n "${LOCAL_JAR_FILE}" ] && [ -f "${LOCAL_JAR_FILE}" ]; then
  BINTRAY_JAR_URL="${BINTRAY_BASE_URL}${BINTRAY_CONTENT_PATH}/${BINTRAY_ART_NAME}-${BINTRAY_ART_VERSION}.jar"
  upload_file "${LOCAL_JAR_FILE}" "${BINTRAY_JAR_URL}" "-" "jar"
else
  printf "\n"
  log "INFO" "$(printf "SKIP JAR: %s" "${LOCAL_JAR_FILE:-NULL}")"
fi

# SOURCES

LOCAL_SOURCE_JAR_FILE="/github/workspace/${INPUT_SOURCE_JAR_FILE_NAME}"
if [ -n "${LOCAL_SOURCE_JAR_FILE}" ] && [ -f "${LOCAL_SOURCE_JAR_FILE}" ]; then
  BINTRAY_SOURCE_JAR_URL="${BINTRAY_BASE_URL}${BINTRAY_CONTENT_PATH}/${BINTRAY_ART_NAME}-${BINTRAY_ART_VERSION}-sources.jar"
  upload_file "${LOCAL_SOURCE_JAR_FILE}" "${BINTRAY_SOURCE_JAR_URL}" "sources" "jar"
else
  printf "\n"
  log "INFO" "$(printf "SKIP SOURCE JAR: %s" "${LOCAL_SOURCE_JAR_FILE:-NULL}")"
fi

# JAVADOC

LOCAL_JAVADOC_JAR_FILE="/github/workspace/${INPUT_JAVADOC_JAR_FILE_NAME}"
if [ -n "${LOCAL_JAVADOC_JAR_FILE}" ] && [ -f "${LOCAL_JAVADOC_JAR_FILE}" ]; then
  BINTRAY_JAVADOC_JAR_URL="${BINTRAY_BASE_URL}${BINTRAY_CONTENT_PATH}/${BINTRAY_ART_NAME}-${BINTRAY_ART_VERSION}-javadoc.jar"
  upload_file "${LOCAL_JAVADOC_JAR_FILE}" "${BINTRAY_JAVADOC_JAR_URL}" "javadoc" "jar"
else
  printf "\n"
  log "INFO" "$(printf "SKIP JAVADOC JAR: %s" "${LOCAL_JAVADOC_JAR_FILE:-NULL}")"
fi

printf "\n\n"
log "WARN" "All done, you can check and publish your package at Bintray"
printf "\n\n"
