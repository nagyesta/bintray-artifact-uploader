#!/bin/sh -l

IMAGE_NAME=$1
INPUT_DIR_WORKSPACE=$2
OUTPUT_FILE_EXIT_CODE=$3
OUTPUT_FILE_STD_OUTPUT=$4

export INPUT_API_KEY="api-key"
export INPUT_API_USER="api-user"

export INPUT_BASE_URL="http://bau-wiremock:8080/empty/"
export INPUT_SUBJECT="subject"
export INPUT_REPO="repo-name"
export INPUT_PACKAGE_NAME="package-name"

export INPUT_DEBUG_LOG="true"
export INPUT_DRY_RUN="false"

export INPUT_ARTIFACT_GROUP_ID="com.github.gh-user"
export INPUT_ARTIFACT_ARTIFACT_ID="artifact.name"
export INPUT_ARTIFACT_VERSION="1.2.3"

export INPUT_POM_FILE_NAME="pom.xml"
export INPUT_JAR_FILE_NAME="dummy-?.?.?.jar.content"
export INPUT_SOURCE_JAR_FILE_NAME="dummy-1.2.3-sources.jar.content"
export INPUT_JAVADOC_JAR_FILE_NAME="dummy-1.2.3-javadoc.jar.content"

docker run --rm --name bau-main -v "${INPUT_DIR_WORKSPACE}:/github/workspace/" \
  -e INPUT_ARTIFACT_GROUP_ID \
  -e INPUT_ARTIFACT_ARTIFACT_ID \
  -e INPUT_ARTIFACT_VERSION \
  -e INPUT_DEBUG_LOG \
  -e INPUT_DRY_RUN \
  -e INPUT_API_USER \
  -e INPUT_REPO \
  -e INPUT_API_KEY \
  -e INPUT_PACKAGE_NAME \
  -e INPUT_POM_FILE_NAME \
  -e INPUT_JAR_FILE_NAME \
  -e INPUT_SOURCE_JAR_FILE_NAME \
  -e INPUT_JAVADOC_JAR_FILE_NAME \
  -e INPUT_BASE_URL \
  -e INPUT_SUBJECT \
  --link bau-wiremock \
  "${IMAGE_NAME}" > "${OUTPUT_FILE_STD_OUTPUT}"

echo "$?" > "${OUTPUT_FILE_EXIT_CODE}"
