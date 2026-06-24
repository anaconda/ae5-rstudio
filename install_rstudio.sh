#!/bin/bash

echo "+-----------------------+"
echo "| AE5 RStudio Installer |"
echo "+-----------------------+"

if [[ -z "$TOOL_PROJECT_URL" || -z "$TOOL_HOST" || -z "$TOOL_OWNER" ]]; then
    echo 'ERROR: this script must be run within an AE5 session.'
    exit -1
elif ! grep -q /tools/ /opt/continuum/scripts/start_user.sh; then
    echo 'ERROR: this version of the RStudio Installer requires AE5.5.1 or later.'
    exit -1
elif [ -z "$RSTUDIO_PREFIX" ]; then
    RSTUDIO_PREFIX=/tools/rstudio
elif [ $RSTUDIO_PREFIX = /tools/rstudio ]; then
    :
elif [ $RSTUDIO_PREFIX != /usr/lib/rstudio-server ]; then
    echo "ERROR: RStudio must be installed in one of the following directories:"
    echo "- /tools/rstudio"
    echo "- /usr/lib/rstudio-server"
    echo "The first is strongly preferred. Please refer to README.md for details."
    exit -1
fi

RSTUDIO_PARENT=$(dirname $RSTUDIO_PREFIX)
if [[ -d $RSTUDIO_PREFIX || $RSTUDIO_PREFIX != /tools/rstudio ]]; then
    if [ ! -d $RSTUDIO_PREFIX ]; then
        echo "The directory $RSTUDIO_PREFIX is missing. Please add this volume"
        echo "to your configuration, then stop and restart this session."
        exit -1
    elif [ ! -w $RSTUDIO_PREFIX ]; then
        echo "The directory $RSTUDIO_PREFIX is readonly. Please ensure that its"
        echo "volume is set to read-write, then stop and restart this session."
        exit -1
    elif [ ! -z "$(ls -A $RSTUDIO_PREFIX)" ]; then
        echo "The directory $RSTUDIO_PREFIX is not empty. To prevent overwriting an"
        echo "existing installation, the script expects this directory to be empty."
        echo "Please manually remove the contents before proceeding."
        ls -A $RSTUDIO_PREFIX
        exit -1
    fi
elif [ ! -d $RSTUDIO_PARENT ]; then
    echo "ERROR: The directory $RSTUDIO_PARENT is missing. Please follow the instructions"
    echo "in README.md to create this volume, and stop and restart this session."
    exit -1
elif [ ! -w $RSTUDIO_PARENT ]; then
    echo "ERROR: The directory $RSTUDIO_PARENT is readonly. Please follow the instructions"
    echo "in README.md to set it to read-write, and stop and restart this session."
    exit -1
fi

echo "- Install prefix: $RSTUDIO_PREFIX"

# RHEL 10 (UBI 10) ships OpenSSL 3 only and has no rhel10 RStudio build; use
# the rhel9 RPM, which links against OpenSSL 3 and runs on UBI 10. The rhel8
# build needs OpenSSL 1.1 (libssl.so.1.1) and crash-loops on UBI 10.
if grep -qE 'release (9|10)' /etc/redhat-release; then
    main_ver=9
else
    main_ver=8
fi

missing=
for v in $main_ver; do
    fname=rs-centos$v.rpm
    [ -f $fname ] || [ -f data/$fname ] || missing="$missing$fname "
done
if [ -n "$missing" ]; then
    echo "ERROR: one or more of the RStudio missing:"
    echo "- $missing"
    echo "Please follow the directions in README.md to"
    echo "bring these binaries into the project."
    exit -1
fi

for fname in Rprofile configure_env.sh rsession.sh \
    start_rstudio.sh default_env.py profile.sh; do
    [ -e $fname ] || missing=$missing"$fname "
done
if [ ! -z "$missing" ]; then
    echo "One or more of the installer support files is missing:"
    echo "- $missing"
    echo "Please restore the full contents of the installer project."
    exit -1
fi

for v in $main_ver; do
    fname=rs-centos$v.rpm
    [ -f $fname ] || fname=data/$fname
    echo "- Verifying $fname"
    if ! rpm2cpio $fname >/dev/null; then
        echo "- ERROR: $fname is not a valid RPM package. Please remove this file and re-download it."
        exit -1
    fi
done

if [ ! -d $RSTUDIO_PREFIX ]; then
    echo "- Creating directory $RSTUDIO_PREFIX"
    if ! mkdir -p $RSTUDIO_PREFIX; then
        echo "ERROR: The directory $RSTUDIO_PREFIX could not be created. Because the"
        echo "parent directory $RSTUDIO_PARENT is writable, this is unexpected. Please correct"
        echo "this issue before proceeding further."
        exit -1
    fi
fi

first=yes

for v in $main_ver; do
    echo "- Unpacking RHEL${v}/CentOS${v} package"
    mkdir -p $RSTUDIO_PREFIX/staging${v}/usr/lib/rstudio-server
    fname=rs-centos${v}.rpm
    [ -f $fname ] || fname=data/$fname
    rpm2cpio $fname | (cd $RSTUDIO_PREFIX/staging${v} && cpio -ic)
done

echo "- Moving files into final position"
mv $RSTUDIO_PREFIX/staging${main_ver}/usr/lib/rstudio-server/* $RSTUDIO_PREFIX
rm -rf $RSTUDIO_PREFIX/staging*

echo "- Installing support files"
cp -rf Rprofile configure_env.sh rsession.sh \
    start_rstudio.sh default_env.py skeleton $RSTUDIO_PREFIX/
cp profile.sh $RSTUDIO_PREFIX/resources/terminal/hooks
find $RSTUDIO_PREFIX/skeleton -name '.keep' -exec rm -f {} \; || :
chmod +x $RSTUDIO_PREFIX/{start_rstudio.sh,rsession.sh}

echo "+-----------------------+"
echo "RStudio installation is complete."
echo "Once you have verified the installation, feel free to"
echo "shut down this session and delete the project."
echo "+-----------------------+"
if [ ! -d /tools/java ]; then
    echo "WARNING: Many R packages make use of Java, and it seems"
    echo "not to be present on this installation of AE5. To make"
    echo "Java available to all AE5 users, run install_java.sh, or"
    echo "manually download a JDK Linux x64 archive and unpack its"
    echo "contents into the directory /tools/java."
echo "+-----------------------+"
fi
