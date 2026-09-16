#!/bin/bash

set -euo pipefail
SCRIPT_NAME=$(basename ${BASH_SOURCE[0]})
SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
cd ${SCRIPT_DIR}

expected_version=$(sed -nE 's@-@.@g;s@[.]0+@.@g;s@.*RSTUDIO_VERSION=@@p' download_rstudio.sh)
expected_env=/opt/continuum/anaconda/envs/anaconda50_r
container_name=ae5-rstudio-test

if [ -d /opt/continuum/anaconda/conda-meta ]; then

	# Inside the container: download RStudio and install it
	err_exit() { echo "-- FAILED --"; exit 1; }
	export DOWNLOAD_DIR=/tools
	export TOOL_PROJECT_URL=@ TOOL_HOST=@ TOOL_PORT=8086
	source /opt/continuum/anaconda/etc/profile.d/conda.sh
	conda config --set number_channel_notices 0
	conda activate base
	git config --global --add safe.directory "$SCRIPT_DIR"
	if [ $(uname -m) == "aarch64" ]; then arch=aarch64; else arch=x86_64; fi
	echo ""
	bash download_rstudio.sh 2>&1
	echo ""
	bash install_rstudio.sh 2>&1
	echo ""
	conda create -q -p "$expected_env" --override-channels -c conda-forge r-irkernel --yes 2>&1
	echo ""
	touch ~/prepare.log
	bash /tools/rstudio/start_rstudio.sh 2>&1
	exit 0

fi

# Only one container can run at a time
if [ -n "$(docker ps -aq -f name="^${container_name}$")" ]; then
	echo "Container $container_name is already running" 1>&2
	exit 1
fi

# Query GitHub for the latest production container version
if [ -z "${IMAGE_VER:-}" ]; then
	# This is a bit of a hack 
	IMAGE_VER=$(curl -s -u "_json_key:$AE_GCR_KEY" \
		https://gcr.io/v2/continuum-compute/ae-editor-base/tags/list | \
		jq -r '.tags[]' | tail -1 | sed -E 's@-(arm64|amd64)@@')
	if [ -z "$IMAGE_VER" ]; then
		echo "Could not determine ae-editor-base image version" 1>&2
		exit -1
	fi
fi
image_name=gcr.io/continuum-compute/ae-editor-base:${IMAGE_VER} 
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	echo "image_ver=${IMAGE_VER}" >> "$GITHUB_OUTPUT"
	echo "expected_version=${expected_version}" >> "$GITHUB_OUTPUT"
fi

# Launch the container in detach mode but give it a name we can track
container_cleanup() { 
	docker stop "$container_name" >/dev/null 2>&1 || :
	docker rm "$container_name" >/dev/null 2>&1 || :
}
trap container_cleanup EXIT
cmd=(docker pull "$image_name")
echo "> ${cmd[*]}"
"${cmd[@]}" >/dev/null
cmd=(docker run --detach --name "$container_name" \
	 --publish 8086:8086 --env TOOL_OWNER=$USER --env TOOL_PACKAGE=bash \
	 --tmpfs /tools:exec -v "${SCRIPT_DIR}:/testing:ro" \
	 "$image_name" bash /testing/${SCRIPT_NAME})
echo "> ${cmd[*]}"
"${cmd[@]}" >/dev/null
docker ps --all --no-trunc | grep -E "${container_name}$" || :
echo ""

# Scan the logs of the container until 1) the container dies;
# 2) it emits the "-- FAILED --" error; or 3) it emits a line
# from start_rstudio.sh indicating RStudio is running. In that
# last case, capture the timestamp so that we can print the rest
# of the logs after the capture attempt.
timestamp=
while IFS= read -r line; do
	echo "${line#* }"
	case "$line" in
	*"- FAILED -"*) break ;;
	*"- END: AE5 RStudio Startup -"*) timestamp="${line%% *}"; break ;;
	esac
done < <(docker logs "$container_name" --follow --timestamps)

if [ -z "$timestamp" ]; then
	echo "RStudio failed to stabilize" 1>&2
	exit 1
fi

# Use the playright script to bring up RStudio, query the RStudio version
# and the R environment, and compare it against expectation. To keep the Docker logs
# continuous we're capturing the node output in a variable, grabbing the rest of the
# logs, and then we'll print the output of the attempt.
capture_attempt=$(node capture.mjs "$expected_version" "$expected_env" 1>&2 && echo "@@success@@" || :)

docker logs "$container_name" --since="$timestamp" | sed 1d

echo "${capture_attempt%*@@success@@}"
[[ "$capture_attempt" = *"@@success@@" ]] || exit 1
