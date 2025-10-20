#!/bin/bash

echo "+------------------------+"
echo "| AE5 RStudio Downloader |"
echo "+------------------------+"

[ $RSTUDIO_VERSION ] || RSTUDIO_VERSION=2025.09.1-401
echo "- Target version: ${RSTUDIO_VERSION}"

if [[ -n "$TOOL_PROJECT_URL" && -d data ]]; then
   echo "- Downloading into the data directory"
   fdir=data/
fi

if [ -z "$TOOL_PROJECT_URL" ]; then
    echo "- Downloading both versions for airgap"
    needed="8 9"
elif grep -q 'release 9' /etc/redhat-release; then
    echo "- Downloading RHEL9 version only"
    needed=9
else
    echo "- Downloading RHEL8 version only"
    needed=8
fi

# We download all three RPM versions here so we can ensure what we need
# for every supported version of AE5 and R.
for os_ver in $needed; do
    what_os="RHEL${os_ver}/CentOS${os_ver}"
    fname=${fdir}rs-centos${os_ver}.rpm
    echo "- Downloading $what_os RPM file to $fname"
    for os_base in rhel centos; do
        url=https://download2.rstudio.org/server/${os_base}${os_ver}/x86_64/rstudio-server-rhel-${RSTUDIO_VERSION}-x86_64.rpm
        echo "- URL: $url"
        if ! curl -o $fname -L $url; then
           echo "- unexpected error with curl"
           continue
        elif grep -q NoSuchKey $fname; then
           echo "- bucket error downloading package"
           rm -f $fname
           continue
        fi
        break
    done
    if [ ! -f $fname ]; then
        echo "- ERROR: could not find package as expected. Please check URLs."
        exit -1
    fi
    if which rpm2cpio &>/dev/null; then
        echo "- Verifying $fname"
        if ! rpm2cpio $fname >/dev/null; then
            echo "- ERROR: $fname is not a valid RPM package. Please remove this file and re-download it."
            exit -1
        fi
    fi
done

echo "+------------------------+"
echo "The RStudio binaries have been downloaded."
if [ -z "$TOOL_PROJECT_URL" ]; then
    echo "Upload these files to your installer session to proceed."
else
    echo "You may now proceed with the installation step."
fi
echo "See the README.md file for more details."
echo "+------------------------+"
