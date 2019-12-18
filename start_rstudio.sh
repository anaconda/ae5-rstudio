#!/bin/bash

rm -rf ~/.rstudio
killall rsession 2>/dev/null

# source /opt/continuum/anaconda/bin/activate anaconda44_r
# same here only anaconda44_r for anaconda 5.4
source /opt/continuum/anaconda/bin/activate anaconda44_r
env | grep ^CONDA > ~/.Renviron
echo PATH=$PATH >> ~/.Renviron
echo session-default-working-dir=/opt/continuum/project > ~/.rsession.conf
echo session-rprofile-on-resume-default=1 >> ~/.rsession.conf

# Translate AE environment variables to Rstudio command-line arguments
# --rsession-which-r /opt/continuum/anaconda/envs/anaconda44_r/bin/R \
args=(/usr/lib/rstudio-server/bin/rserver \
      --rsession-config-file ~/.rsession.conf \
      --rsession-path /opt/continuum/scripts/rsession.sh \
      --auth-none=1 --auth-validate-users=0 --auth-minimum-user-id=16 \
      --server-working-dir=/opt/continuum)
[[ $TOOL_PORT ]] && args+=(--www-port=$TOOL_PORT)
[[ $TOOL_ADDRESS ]] && args+=(--www-address=$TOOL_ADDRESS)
[[ $TOOL_IFRAME_HOSTS ]] && args+=(--www-frame-origin=$TOOL_IFRAME_HOSTS)

echo "${args[@]}"
exec "${args[@]}"
