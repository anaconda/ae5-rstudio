#!/bin/bash

echo "+------------------------+"
echo "| AE5 RStudio Downloader |"
echo "+------------------------+"

[ $RSTUDIO_VERSION ] || RSTUDIO_VERSION=2026.07.1-147
echo "- Target version: ${RSTUDIO_VERSION}"

if [[ -n "$TOOL_PROJECT_URL" && -d data ]]; then
   echo "- Downloading into the data directory"
   fdir=data/
fi

if [ $(uname -m) == "aarch64" ]; then
    arches="aarch64"
else
    arches="x86_64"
fi

if [ -z "$TOOL_PROJECT_URL" ]; then
    echo "- Downloading all versions for airgap"
    needed="8 9"
    arches="x86_64 aarch64"
elif grep -qE 'release (9|10)' /etc/redhat-release; then
    # RHEL 10 ships OpenSSL 3 only (no libssl.so.1.1); RStudio has no rhel10
    # build yet, so use the rhel9 RPM, which is linked against OpenSSL 3 and
    # runs on UBI 10. (The rhel8 build needs OpenSSL 1.1 and crash-loops here.)
    echo "- Downloading RHEL9 version only"
    needed=9
else
    echo "- Downloading RHEL8 version only"
    needed=8
fi

# We download all three RPM versions here so we can ensure what we need
for arch in $arches; do for os_ver in $needed; do
    if [[ "$arch" != "x86_64" && "$os_ver" != "9" ]]; then continue; fi
    fname=${fdir}rs-rhel${os_ver}-${arch}.rpm
    echo "- Downloading RHEL$os_ver ${arch} RPM file to $fname"
    if [ "$arch" = "x86_64" ]; then
        url=https://download2.rstudio.org/server/rhel${os_ver}/x86_64/rstudio-server-rhel-${RSTUDIO_VERSION}-x86_64.rpm
    else
        url=https://dl.dailies.rstudio.com/server/rhel${os_ver}/arm64/rstudio-server-rhel-${RSTUDIO_VERSION}-aarch64.rpm
    fi
    echo "- URL: $url"
    if ! curl -o $fname -L $url; then
       echo "- unexpected error with curl"
       exit 1
    elif grep -q NoSuchKey $fname; then
       echo "- bucket error downloading package"
       rm -f $fname
       exit 1
    elif [ ! -f $fname ]; then
        echo "- ERROR: could not find package as expected. Please check URLs."
        exit -1
    elif which rpm2cpio &>/dev/null; then
        echo "- Verifying $fname"
        if ! rpm2cpio $fname >/dev/null; then
            echo "- ERROR: $fname is not a valid RPM package. Please remove this file and re-download it."
            exit -1
        fi
    fi
done; done

echo "+------------------------+"
echo "The RStudio binaries have been downloaded."
if [ -z "$TOOL_PROJECT_URL" ]; then
    echo "Upload these files to your installer session to proceed."
else
    echo "You may now proceed with the installation step."
fi
echo "See the README.md file for more details."
echo "+------------------------+"
