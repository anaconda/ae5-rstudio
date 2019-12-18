#!/usr/bin/env bash
# identify valid AE versions and matching R environments
# check that we are really removing the image from the registry not only from docker engine -- does docker rmi removes from registry or local docker engine only? 

# this is the cloned repo - i.e. 
# git clone https://github.com/Anaconda-Platform/ae5-rstudio.git
# I used this script from ae5-rstudio/.. (parent) did not test from local folder and it will probably not work..

export SRC="ae5-rstudio"
export  pgpod=$(kubectl get pods | awk '/postgres/  { print $1 }')
export  pcmd=$(kubectl get pods | awk '/postgres/ { print "kubectl exec -it "$1"  -- /usr/bin/psql -qt -U postgres "}')
export WORKSPACE=$(kubectl set env deploy --all --list | awk -F= '/EDITOR/ {print $2}')

# echo=echo  # for debug
docker() {
  # use gravity docker
  sudo gravity exec -t docker $@
}

psql() {
  pcmd=$(kubectl get pods | awk '/postgres/ { print "kubectl exec -it "$1"  -- /usr/bin/psql -qt -U postgres "}')
  [[ ! -z $1 ]] && pcmd="$pcmd -d $1"
  [[ ! -z $2 ]] && pcmd="$pcmd -c \"$2\""
  eval "$pcmd"
}

get_current_tools() {
  [[ "$1" == "json" ]] && psql anaconda_ui "select options from integration where name='workspace';" | tr -d [[:cntrl:]] 
  [[ -z $1 ]] && psql anaconda_ui "select options from integration where name='workspace';" | tr -d [[:cntrl:]] | jq -r '.workspace.tools|keys[]' | tr '\n' ',  ' | sed 's/,$/\n/'
}

rm_docker_image_for_editor() {
  export editor=${1:-rstudio}
  echo removing image for $editor
  image=$(docker image ls | grep $editor)
  [[ -n $image ]] && cmd="docker rmi $(echo $image | awk '{print $1":"$2}')" && echo $cmd
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
  fi
}

rm_editor_workspace() {
  echo checking for session using the $editor image 
  stop_editor_sessions $editor  
  [[ ! $WORKSPACE =~ $editor ]] && echo looks like $editor image is not in deployment $WORKSPACE exiting...  && return 1
  
  for deployment in workspace 
  do 
    echo modifying $deployment to use new docker image ${WORKSPACE}-${editor}
    kubectl get deploy anaconda-enterprise-ap-${deployment}  -o yaml --export > ${deployment}.org.yml
    sed "s#-${editor}##g" ${deployment}.org.yml > ${deployment}.new.yml
    # add sanity check on the change
    [[ $(diff  workspace.*.yml | egrep '<|>' -c) != 2 ]] && echo unexpected diff output stopping - check manually the yaml files && return 1 
    $echo kubectl replace -f ${deployment}.new.yml
  done
}

add_editor_workspace() {
  [[ $WORKSPACE =~ $editor ]] && echo looks like image already has $editor modification $WORKSPACE exiting...  && return 1
  for deployment in workspace 
  do 
    kubectl get deploy anaconda-enterprise-ap-${deployment}  -o yaml --export > ${deployment}.org.yml
    sed "s#${WORKSPACE}#${WORKSPACE}-${editor}#g" ${deployment}.org.yml > ${deployment}.new.yml
    [[ $(diff  workspace.*.yml | egrep '<|>' -c) != 2 ]] && echo unexpected diff output stopping - check manually the yaml files && return 1 
    $echo kubectl replace -f ${deployment}.new.yml
  done
}

add_editor_pg(){
  export tool=${1:-rstudio}
  get_current_tools
  echo 
  [[ $(get_current_tools | grep $tool) ]] && echo $tool already in db && return 1 
  VALUE="$(cat $SRC/workspace-new.json | jq -c '.')"
  echo "update integration set options='$VALUE' where name='workspace';" > sql
  kubectl cp ./sql $pgpod:/tmp
  eval "$pcmd -d anaconda_ui -f /tmp/sql"
  sleep 5
  get_current_tools
  echo
}

rm_editor_pg() {
  export tool=${1:-rstudio}
  get_current_tools 
  echo
  [[ ! $(get_current_tools | grep $tool) ]] && echo $tool is not in db && return 1
  echo removing $tool
  export VALUE="$(get_current_tools json | jq -c --arg tool $tool  '.|del(.workspace.tools[$tool])')"
  #echo "$VALUE"
  echo "update integration set options='$VALUE' where name='workspace';" > sql
  kubectl cp ./sql $pgpod:/tmp
  eval "$pcmd -d anaconda_ui -f /tmp/sql"
  sleep 5
  get_current_tools
  echo
}


rstudio_prep() {
  editor=${1:-rstudio}
  [[ ! -d /opt/anaconda/${editor} ]] && mkdir /opt/anaconda/${editor} 
  [[ -d /opt/anaconda/${editor} ]] && cp -r ${SRC}/* /opt/anaconda/${editor}
  pushd  /opt/anaconda/${editor}
  [[ ! -f rstudio-server-rhel-1.2.1335-x86_64.rpm ]] &&  curl -kO https://download2.rstudio.org/server/centos6/x86_64/rstudio-server-rhel-1.2.1335-x86_64.rpm 
  [[ ! -f psmisc-22.20-16.el7.x86_64.rpm ]] && curl -kO https://rpmfind.net/linux/centos/7.7.1908/os/x86_64/Packages/psmisc-22.20-16.el7.x86_64.rpm 
  popd
}

editor() {
  export op=${1:-add}
  export editor=${2:-rstudio}
  echo current image is $WORKSPACE
  if [[ $op == "rm" ]];
  then 
    ${op}_editor_pg $editor
    ${op}_editor_workspace $editor
    ${op}_docker_image_for_editor $editor
  elif [[ $op == "add" ]];
  then
    ${op}_docker_image_for_editor $editor
    ${op}_editor_pg $editor 
    ${op}_editor_workspace $editor
  fi
}

add_rstudio() {
  rstudio_prep rstudio 
  editor add rstudio 
}  

[[ $1 == "add" ]] && [[ $2 == "rstudio" ]] && add_rstudio
[[ $1 == "rm" ]] && [[ $2 == "rstudio" ]] && editor rm rstudio
