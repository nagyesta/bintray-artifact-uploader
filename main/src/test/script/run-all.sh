#!/bin/sh -l

IMAGE_NAME=$1
INPUT_DIR_WORKSPACE=$2
OUTPUT_DIR=$3

sleep 2

for FILE_NAME in * ; do
  if [ "${FILE_NAME}" != "run-all.sh" ] ; then
    BASE_FILE_NAME="$(echo "${FILE_NAME}" | sed 's/.sh$//')"
    sh "${FILE_NAME}" "${IMAGE_NAME}" "${INPUT_DIR_WORKSPACE}" "${OUTPUT_DIR}/${BASE_FILE_NAME}.exitcode.txt" "${OUTPUT_DIR}/${BASE_FILE_NAME}.output.txt"
  fi
done
