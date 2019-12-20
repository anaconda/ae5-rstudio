#!/usr/bin/env bash
# identify valid AE versions and matching R environments
# check that we are really removing the image from the registry not only from docker engine -- does docker rmi removes from registry or local docker engine only? 
# git clone https://github.com/Anaconda-Platform/ae5-rstudio.git
# for this to work you need working ae5-tools and yq


# echo=echo  # for debug
export SRC="."
export WORKSPACE=$(kubectl set env deploy --all --list | awk -F= '/EDITOR/ {print $2}')


docker() {
  # use gravity docker
  sudo gravity exec -t docker $@
}

rm_docker_image_for_editor() {
  export editor=${1:-rstudio}
  echo removing image for $editor
  image=$(docker image ls | grep $editor)
  if [[ -n $image ]]; then
    cmd="docker rmi $(echo $image | awk '{print $1":"$2}')" 
    echo trying to remove image, may need to wait a little...  - $cmd
    t=10 
    while [[ $t -gt 0 ]]
    do  
      t=$((t-1))
      printf .
      sleep 6
      eval "$cmd" 2>/dev/null && t=0
    done
    [[ ! $? ]] && echo docker image was not removed
fi
  # todo:
  echo remove from docker registry
}

add_docker_image_for_editor() {
 export editor=${1:-rstudio}
 sed -i "s@^FROM .*@FROM $WORKSPACE@" /opt/anaconda/${editor}/Dockerfile
 echo checking for $editor image in local docker engine 
 is_already_there=$(docker image ls | grep -c $editor)
 if [[ $is_already_there == "0" ]]; then 
   echo building new docker container for $editor
   echo current dir $(pwd) and files in dir are $(ls)
   cmd="--build-arg WORKSPACE=$WORKSPACE -t ${WORKSPACE}-${editor} -f /opt/anaconda/${editor}/Dockerfile /opt/anaconda/${editor}  --force-rm "
   echo about to execute docker build in planet container with this cmd - $cmd
   docker build $cmd
   [[ $? == 0 ]] && docker push  ${WORKSPACE}-${editor} 
 else
   echo $editor image alreadt in local docker engine
   echo TODO: add check for image in registry
   return 1
 fi 
}

stop_editor_sessions() {
  export editor=${1:-rstudio}
  # check for pods using the image 
  containers="$(kubectl get pods -o=jsonpath='{range .items[*]}{"\n"}{.metadata.name}{":"}{range .spec.containers[*]}{.image}{","}{end}{end}{"\n"}' \
       | sed -nE 's@([^:]+):.*-rstudio.*@\1@p')"

  if [[ -n $containers ]]; then
    echo there seems to be sessions running using the $editor image
    read -p "Shoul I try and stop the running sessions? (y/n): " ans
    [[ $ans != "y" ]] && echo please stop sessions before modifying the deployment... exiting && return 1
    [[ ! $(ae5 session list 2>/dev/null ) ]] && echo "ae5 session list" did not run successfully, this is required for stopping sessions && exit -1
    for container in $containers
    do
      id=$(ae5 session list --no-header --columns id  | grep "$(echo $container | awk -F- '{print $3}')")
      ae5 session stop --yes $id
    done 
  else
    echo no current running sessions - you still need to change existing projects that has RSTudio as their editor to a different editor
    echo TODO: automate this too.
  fi
}

rm_editor_workspace_deployment() {
  echo checking for session using the $editor image 
  stop_editor_sessions $editor  
  [[ ! ${WORKSPACE} =~ $editor ]] && echo looks like $editor image is not in deployment $WORKSPACE exiting...  && return 1
  
  for deployment in workspace 
  do 
    echo modifying $deployment to ${WORKSPACE}
    kubectl get deploy anaconda-enterprise-ap-${deployment}  -o yaml --export > ${deployment}.org.yml
    sed "s#-${editor}##g" ${deployment}.org.yml > ${deployment}.new.yml
    # add sanity check on the change
    [[ $(diff  workspace.*.yml | egrep '<|>' -c) != 2 ]] && echo unexpected diff output stopping - check manually the yaml files && return 1 
    $echo kubectl replace -f ${deployment}.new.yml
  done
}

add_editor_workspace_deployment() {
  [[ $WORKSPACE =~ $editor ]] && echo looks like image already has $editor modification $WORKSPACE exiting...  && return 1
  for deployment in workspace 
  do 
    kubectl get deploy anaconda-enterprise-ap-${deployment}  -o yaml --export > ${deployment}.org.yml
    sed "s#${WORKSPACE}#${WORKSPACE}-${editor}#g" ${deployment}.org.yml > ${deployment}.new.yml
    [[ $(diff  workspace.*.yml | egrep '<|>' -c) != 2 ]] && echo unexpected diff output stopping - check manually the yaml files && return 1 
    $echo kubectl replace -f ${deployment}.new.yml
  done
}

## ConfigMap change ##
get_ae_cm_api() {
  local l="$(kubectl get cm anaconda-enterprise-anaconda-platform.yml  -o yaml)"
  echo "$l"
}

get_ae_cm() { # extract the yaml from the config map, input keys=list all root keys, git show git section, any other key wil present the key only
  [[ -z $1 ]] && src="$(get_ae_cm_api)" 
  [[ -n $1 ]] && sec="$1"
  conf="$(echo "$src"  | yq -r '.data[]')"
  echo "$(echo "$conf" | yq -r -y "$jq_path")"
}

filter_k8s_ins_data(){
    for flt in $* .metadata.creationTimestamp .metadata.resourceVersion .metadata.selfLink .metadata.uid
    do
      filter="del($flt)|$filter"
    done
    yq -r -y "$filter."
}

get_ae_workspace_tools() {
   [[ "$1" == "json" ]] &&  get_ae_cm | yq '.ui.services["anaconda-workspace"].workspace.options.workspace.tools'
   [[ -z "$1" ]] &&  get_ae_cm | yq -r '.ui.services["anaconda-workspace"].workspace.options.workspace.tools|keys|join(", ")' | sed 's/,$/\n/'
}

rm_editor_ae_cm(){
  export tool=${1:-rstudio}
  get_ae_workspace_tools
  [[ $(get_ae_workspace_tools  | grep $tool) ]] || (echo $tool not in cm && return 1)
  # CONF 
  export VALUE="$(get_ae_workspace_tools json | jq -c --arg tool $tool  '.|del(.workspace.tools[$tool])')"
  # API
  export NEWVAL="$(get_ae_cm | yq -y  --argjson val "$VALUE" '.ui.services["anaconda-workspace"].workspace.options.workspace.tools=$val')"
  get_ae_cm_api  | filter_k8s_ins_data | yq -r -y --arg a "$NEWVAL" '.data["anaconda-platform.yml"]=$a' > anaconda-enterprise-${editor}.yml
  kubectl replace -f anaconda-enterprise-${editor}.yml
  [[ $(uipod) ]] && kubectl delete pod $(uipod)
  while [[ $(uipod) ]]; do sleep 5; printf . ; done; echo ready
  get_ae_workspace_tools
}

add_editor_ae_cm(){
  export tool=${1:-rstudio}
  get_ae_workspace_tools
  [[ $(get_ae_workspace_tools  | grep $tool) ]] && echo $tool already in cm && return 1 
  get_ae_workspace_tools json > tools.json
  # CONF
  export VALUE="$(jq -S -s '.[0]*.[1]' tools.json ${editor}.json)"
  # API
  export NEWVAL="$(get_ae_cm | yq -y  --argjson val "$VALUE" '.ui.services["anaconda-workspace"].workspace.options.workspace.tools=$val')"
  get_ae_cm_api  | filter_k8s_ins_data | yq -r -y --arg a "$NEWVAL" '.data["anaconda-platform.yml"]=$a' > anaconda-enterprise-${editor}.yml
  kubectl replace -f anaconda-enterprise-${editor}.yml
  [[ $(uipod) ]] && kubectl delete pod $(uipod)
  while [[ $(uipod) ]]; do sleep 5; printf . ; done; echo ready
  get_ae_workspace_tools
}

uipod() {
 kubectl get pods  | awk '/-ap-ui-/ {if ($3=="Running") print $1}'
}

rstudio_prep() {
  editor=${1:-rstudio}
  [[ ! -d /opt/anaconda/${editor} ]] && mkdir /opt/anaconda/${editor} 
  [[ -d /opt/anaconda/${editor} ]] && cp -r ${SRC}/* /opt/anaconda/${editor}
  [[ ! -f rstudio-server-rhel-1.2.1335-x86_64.rpm ]] &&  curl -kO https://download2.rstudio.org/server/centos6/x86_64/rstudio-server-rhel-1.2.1335-x86_64.rpm 
  [[ ! -f psmisc-22.20-16.el7.x86_64.rpm ]] && curl -kO https://rpmfind.net/linux/centos/7.7.1908/os/x86_64/Packages/psmisc-22.20-16.el7.x86_64.rpm 
}

editor() {
  pushd  /opt/anaconda/${editor}
  export op=${1:-add}
  export editor=${2:-rstudio}
  echo current image is ${WORKSPACE}
  if [[ $op == "rm" ]];
  then 
    ${op}_editor_ae_cm $editor
    ${op}_editor_workspace_deployment $editor
    ${op}_docker_image_for_editor $editor
  elif [[ $op == "add" ]];
  then
    ${op}_docker_image_for_editor $editor
    ${op}_editor_ae_cm $editor 
    ${op}_editor_workspace_deployment $editor
  fi
  popd
}

add_rstudio() {
  rstudio_prep rstudio 
  editor add rstudio 
}  

cleanup() {
  rm workspace.*
  rm sql
  rm tools.json
}

[[ $1 == "add" ]] && [[ $2 == "rstudio" ]] && add_rstudio
[[ $1 == "rm" ]] && [[ $2 == "rstudio" ]] && editor rm rstudio
