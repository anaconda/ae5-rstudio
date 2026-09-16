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
	conda activate base
	if [ $(uname -m) == "aarch64" ]; then arch=aarch64; else arch=x86_64; fi
	bash download_rstudio.sh 2>&1
	bash install_rstudio.sh 2>&1
	conda create -q -p "$expected_env" conda-forge::r-irkernel --yes 2>&1
	touch ~/prepare.log
	bash /tools/rstudio/start_rstudio.sh 2>&1
	exit 0

fi

# Only one container can run at a time
if [ -n "$(docker image ls "$container_name" -q)" ]; then
	echo "Container $container_name is already running" 1>&2
	exit 1
fi

# Query GitHub for the latest production container version
if [ -z "${IMAGE_VER:-}" ]; then
	IMAGE_VER=$(gh api repos/anaconda/anaconda-platform/contents/Makefile.images | \
		jq -r '.content' | base64 -d | \
		sed -nE 's@tag_ae_editor_base *:= *([^ $]*).*@\1@p' || :)
	if [ -z "$IMAGE_VER" ]; then
		echo "Could not determine ae-editor-base image version" 1>&2
		exit -1
	fi
fi
image_name=gcr.io/continuum-compute/ae-editor-base:${IMAGE_VER} 
echo "Using $image_name"

# Launch the container in detach mode but give it a name we can track
container_cleanup() { 
	docker stop "$container_name" >/dev/null 2>&1 || :
	docker rm "$container_name" >/dev/null 2>&1 || :
}
trap container_cleanup EXIT
echo "Launching container..."
cmd=(docker run --detach --name "$container_name" \
	 --publish 8086:8086 --env TOOL_OWNER=@,TOOL_PACKAGE=bash \
	 --tmpfs /tools:exec -v "${SCRIPT_DIR}:/opt/continuum/installer" \
	 $image_name bash /opt/continuum/installer/${SCRIPT_NAME})
echo "> ${cmd[*]}"
"${cmd[@]}"

# Scan the logs of the container until 1) the container dies;
# 2) it emits the "-- FAILED --" error; or 3) it emits a line
# from start_rstudio.sh indicating RStudio is running.
success=no
while IFS= read -r line; do
	case "$line" in
	*"- FAILED -"*) break ;;
	*"- END: AE5 RStudio Startup -"*) success=yes; break ;;
	esac
done < <(docker logs "$container_name" --follow)
if [ "$success" != yes ]; then
	echo "RStudio failed to stabilize; logs:" 1>&2
	docker logs "$container_name" 1>&2
	exit 1
fi

# Use the playright script to bring up RStudio, query the RStudio version
# and the R environment, and compare it agai
echo "RStudio is up and running"
if node capture.mjs "$expected_version" "$expected_env"; then
	echo "RStudio succeeded; screenshot generated"
else
	echo "Unexpected issue obtaining screenshot"
fi