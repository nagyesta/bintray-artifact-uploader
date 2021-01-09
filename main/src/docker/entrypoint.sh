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
export ENABLED_LOG_LEVEL_INFO=${INPUT_INFO_LOG:-true}
export ENABLED_LOG_LEVEL_WARN=${INPUT_WARN_LOG:-true}
export ENABLED_LOG_LEVEL_ERROR=${INPUT_ERROR_LOG:-true}

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
  if [ "$(get_value_of "ENABLED_LOG_LEVEL_${LOG_LEVEL}")" = "true" ]; then
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

validate_input "API_USER"
validate_input "API_KEY"
validate_input "REPO"
validate_input "PACKAGE_NAME"

# Transform input to easier to use format

export DRY_RUN_ONLY="${INPUT_DRY_RUN:-false}"
export BINTRAY_VERSION_PREFIX="${INPUT_BINTRAY_VERSION_PREFIX:-v}"
if [ -z "${INPUT_ARTIFACT_VERSION}" ]; then
  BINTRAY_ART_VERSION=$(git log --format='format:%d' --decorate-refs="refs/tags/${BINTRAY_VERSION_PREFIX}*" -n 1 | grep tag: | sed 's/^.*tag: //' | sed "s/${BINTRAY_VERSION_PREFIX}//" | sed 's/[,)].*$//')
  if [ -z "${BINTRAY_ART_VERSION}" ]; then
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
  if [ "${DRY_RUN_ONLY}" = "false" ]; then
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
  fi
}

log_upload() {
  LOG_UPL_LOCAL_FILE="$1"
  LOG_UPL_BINTRAY_URL="$2"
  LOG_UPL_BINTRAY_ART_GROUP="$3"
  LOG_UPL_BINTRAY_ART_NAME="$4"
  LOG_UPL_BINTRAY_ART_VERSION="$5"
  LOG_UPL_ART_CLASSIFIER="$6"
  LOG_UPL_ART_PACKAGING="$7"

  printf "\n"
  log "INFO" "$(printf "Uploading %s" "${LOG_UPL_LOCAL_FILE}")"
  log "DEBUG" " to"
  log "DEBUG" "$(printf "  %s" "${LOG_UPL_BINTRAY_URL}")"
  log "DEBUG" " as artifact"
  log "DEBUG" "$(printf "  group: %s" "${LOG_UPL_BINTRAY_ART_GROUP}")"
  log "DEBUG" "$(printf "  name: %s" "${LOG_UPL_BINTRAY_ART_NAME}")"
  log "DEBUG" "$(printf "  version: %s" "${LOG_UPL_BINTRAY_ART_VERSION}")"
  log "DEBUG" "$(printf "  classifier: %s" "${LOG_UPL_ART_CLASSIFIER}")"
  log "DEBUG" "$(printf "  packaging: %s" "${LOG_UPL_ART_PACKAGING}")"
}

to_bintray_url() {
  TO_URL_BASE_URL="$1"
  TO_URL_CONTENT_PATH="$2"
  TO_URL_ART_NAME="$3"
  TO_URL_ART_VERSION="$4"
  TO_URL_ART_CLASSIFIER="$5"
  TO_URL_ART_PACKAGING="$6"

  if [ "${TO_URL_ART_CLASSIFIER}" != "-" ]; then
    TO_URL_ART_SUFFIX="-${TO_URL_ART_CLASSIFIER}.${TO_URL_ART_PACKAGING}"
  else
    TO_URL_ART_SUFFIX=".${TO_URL_ART_PACKAGING}"
  fi
  TO_URL_BINTRAY_URL="${TO_URL_BASE_URL}${TO_URL_CONTENT_PATH}/${TO_URL_ART_NAME}-${TO_URL_ART_VERSION}${TO_URL_ART_SUFFIX}"
  printf "%s" "${TO_URL_BINTRAY_URL}"
}

upload_file() {
  UPL_BINTRAY_API_USER="${BINTRAY_API_USER}"
  UPL_BINTRAY_API_KEY="${BINTRAY_API_KEY}"
  UPL_DRY_RUN_ONLY="${DRY_RUN_ONLY}"
  UPL_LOCAL_FILE="$1"
  UPL_BINTRAY_URL="$2"
  UPL_BINTRAY_PACKAGE="$3"
  UPL_BINTRAY_VERSION="$4"

  if [ "${UPL_DRY_RUN_ONLY}" = "false" ]; then
    rm -f response.txt
    if ! curl -s -T "${UPL_LOCAL_FILE}" \
      -o /home/curl_user/response.txt \
      "-u${UPL_BINTRAY_API_USER}:${UPL_BINTRAY_API_KEY}" \
      -H "X-Bintray-Package:${UPL_BINTRAY_PACKAGE}" \
      -H "X-Bintray-Version:${UPL_BINTRAY_VERSION}" \
      "${UPL_BINTRAY_URL}"; then
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
    du -h "${UPL_LOCAL_FILE}" >> /home/curl_user/uploaded_files.txt
    log "INFO" "Upload done."
  else
    log "INFO" "SIMULATION:"
    log "INFO" "$(printf "curl -T %s" "${UPL_LOCAL_FILE}")"
    log "INFO" "$(printf " -u%s:<API_KEY>" "${UPL_BINTRAY_API_USER}")"
    log "INFO" "$(printf " -H \"X-Bintray-Package:%s\"" "${UPL_BINTRAY_PACKAGE}")"
    log "INFO" "$(printf " -H \"X-Bintray-Version:%s\"" "${UPL_BINTRAY_VERSION}")"
    log "INFO" "$(printf " %s" "${UPL_BINTRAY_URL}")"
    du -h "${UPL_LOCAL_FILE}" >> /home/curl_user/uploaded_files.txt
  fi
}

process_file() {
  PRF_BASE_URL="${BINTRAY_BASE_URL}"
  PRF_BT_PACKAGE="${BINTRAY_PACKAGE}"
  PRF_BT_VERSION="${BINTRAY_VERSION}"
  PRF_VERSION="${BINTRAY_ART_VERSION}"
  PRF_BINTRAY_SUBJECT="${BINTRAY_SUBJECT}"
  PRF_BINTRAY_REPO="${BINTRAY_REPO}"
  PRF_LOCAL_FILE="$1"
  PRF_GROUP="$2"
  PRF_ARTIFACT="$3"
  PRF_CLASSIFIER="$(echo "$4" | tr "[:upper:]" "[:lower:]")"
  PRF_PACKAGING="$(echo "$5" | tr "[:upper:]" "[:lower:]")"

  PRF_BINTRAY_PATH=$(echo "${PRF_GROUP}" | sed s/\\./\\//g)
  PRF_CONTENT_PATH="content/${PRF_BINTRAY_SUBJECT}/${PRF_BINTRAY_REPO}/${PRF_BINTRAY_PATH}/${PRF_ARTIFACT}/${PRF_VERSION}"

  if [ "${PRF_CLASSIFIER}" != "-" ]; then
    PRF_TYPE="$(echo "${PRF_CLASSIFIER}" | tr "[:lower:]" "[:upper:]") $(echo "${PRF_PACKAGING}" | tr "[:lower:]" "[:upper:]")"
  else
    PRF_TYPE="$(echo "${PRF_PACKAGING}" | tr "[:lower:]" "[:upper:]")"
  fi

  PRF_URL="$(to_bintray_url "${PRF_BASE_URL}" "${PRF_CONTENT_PATH}" "${PRF_ARTIFACT}" "${PRF_VERSION}" "${PRF_CLASSIFIER}" "${PRF_PACKAGING}")"
  if [ -n "${PRF_LOCAL_FILE}" ] && [ -f "${PRF_LOCAL_FILE}" ]; then
    log_upload "${PRF_LOCAL_FILE}" "${PRF_URL}" "${PRF_GROUP}" "${PRF_ARTIFACT}" "${PRF_VERSION}" "${PRF_CLASSIFIER}" "${PRF_PACKAGING}"
    upload_file "${PRF_LOCAL_FILE}" "${PRF_URL}" "${PRF_BT_PACKAGE}" "${PRF_BT_VERSION}"
  else
    printf "\n"
    log "INFO" "$(printf "SKIP %s: %s" "${PRF_TYPE}" "${PRF_LOCAL_FILE:-NULL}")"
  fi
}

legacy_upload() {
  validate_input "POM_FILE_NAME"
  validate_input "ARTIFACT_GROUP_ID"
  validate_input "ARTIFACT_ARTIFACT_ID"
  export BINTRAY_ART_GROUP="${INPUT_ARTIFACT_GROUP_ID}"
  export BINTRAY_ART_NAME="${INPUT_ARTIFACT_ARTIFACT_ID}"

  create_version_if_missing

  # POM
  LOCAL_POM_FILE="$(ls /github/workspace/${INPUT_POM_FILE_NAME:-UNKNOWN_FILE_DO_NOT_MATCH} 2>/dev/null)"
  process_file "${LOCAL_POM_FILE}" "${BINTRAY_ART_GROUP}" "${BINTRAY_ART_NAME}" "-" "pom"
  # JAR
  LOCAL_JAR_FILE="$(ls /github/workspace/${INPUT_JAR_FILE_NAME:-UNKNOWN_FILE_DO_NOT_MATCH} 2>/dev/null)"
  process_file "${LOCAL_JAR_FILE}" "${BINTRAY_ART_GROUP}" "${BINTRAY_ART_NAME}" "-" "jar"
  # SOURCES
  LOCAL_SOURCE_JAR_FILE="$(ls /github/workspace/${INPUT_SOURCE_JAR_FILE_NAME:-UNKNOWN_FILE_DO_NOT_MATCH} 2>/dev/null)"
  process_file "${LOCAL_SOURCE_JAR_FILE}" "${BINTRAY_ART_GROUP}" "${BINTRAY_ART_NAME}" "sources" "jar"
  # JAVADOC
  LOCAL_JAVADOC_JAR_FILE="$(ls /github/workspace/${INPUT_JAVADOC_JAR_FILE_NAME:-UNKNOWN_FILE_DO_NOT_MATCH} 2>/dev/null)"
  process_file "${LOCAL_JAVADOC_JAR_FILE}" "${BINTRAY_ART_GROUP}" "${BINTRAY_ART_NAME}" "javadoc" "jar"
}

process_manifest() {
  MAN_LOCAL_FILE="$1"

  create_version_if_missing

  # shellcheck disable=SC2002
  cat "${MAN_LOCAL_FILE}" | grep -v "^#" | grep "^\\([^:]\\+:\\)\\{4\\}[^:]\\+$" | while read -r line
  do
    printf "\n"
    log "DEBUG" "Processing line: $line"
    PM_GROUP="$(echo "$line" | cut -d ":" -f 1)"
    PM_ARTIFACT="$(echo "$line" | cut -d ":" -f 2)"
    PM_CLASSIFIER="$(echo "$line" | cut -d ":" -f 3)"
    PM_PACKAGING="$(echo "$line" | cut -d ":" -f 4)"
    PM_FILE_NAME="$(echo "$line" | cut -d ":" -f 5)"

    PM_LOCAL_FILE="$(ls /github/workspace/${PM_FILE_NAME:-UNKNOWN_FILE_DO_NOT_MATCH} 2>/dev/null)"
    log "DEBUG" "File name resolved as: ${PM_LOCAL_FILE}"
    process_file "${PM_LOCAL_FILE}" "${PM_GROUP}" "${PM_ARTIFACT}" "${PM_CLASSIFIER}" "${PM_PACKAGING}"
  done
}

# Start execution

touch /home/curl_user/uploaded_files.txt
LOCAL_MANIFEST="$(ls /github/workspace/"${INPUT_MANIFEST:-UNKNOWN_FILE_DO_NOT_MATCH}" 2>/dev/null)"
if [ -n "${LOCAL_MANIFEST}" ] && [ -f "${LOCAL_MANIFEST}" ]; then
  process_manifest "${INPUT_MANIFEST}"
else
  legacy_upload
fi

printf "\n\n"
log "WARN" "All done, you can check and publish your package at Bintray"
printf "\n"
log "WARN" "Please find the list of uploaded files below:"
# shellcheck disable=SC2002
cat /home/curl_user/uploaded_files.txt | while read -r line; do log "WARN" "$line"; done
printf "\n\n"
