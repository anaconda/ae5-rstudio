#!/bin/bash

# This environment must have an R installation
# CONDA_FALLBACK_ENV=anaconda44_r
# need to find out is this is 5.4 or 5.3 (5.4 does not have anaconda44_r only anaconda44_r)
CONDA_FALLBACK_ENV=anaconda44_r

OC=/opt/continuum
OCA=$OC/anaconda
OCP=$OC/project
OCAB=$OCA/bin
OCLB=$OCA/envs/lab_launch/bin

# RStudio strips out most environment variables before calling
# rsession, for some reason. We want at least the CONDA environment
# to be visible to R, so start_rstudio.sh puts them here
echo "- Reading conda environment variables"
while read -r line; do
    declare -x $line
done < ~/.Renviron
OLD_PFX=$CONDA_PREFIX
echo "- Current environment: $CONDA_DEFAULT_ENV ($CONDA_PREFIX)"
echo "- Current path: $PATH"

# Now determine the environment dictacted by the project, as
# given by the first environment in anaconda-project.yml. If
# this file is broken, we revert to the fallback environment
CONDA_DESIRED_ENV=$(cd $OC/project && $OCLB/anaconda-project list-env-specs </dev/null | grep -A1 ^= | tail -1)
if [ "$CONDA_DESIRED_ENV" ]; then
    echo "- Target environment: $CONDA_DESIRED_ENV"
else
    echo "- Missing or corrupt anaconda-project.yml"
    CONDA_DESIRED_ENV=$CONDA_DEFAULT_ENV
fi

# Switch environments if necessary. However, if the new environment
# does not have R, we need to switch to the fallback.
if [ "$CONDA_DESIRED_ENV" == "$CONDA_DEFAULT_ENV" ]; then
    echo "- No environment change needed"

elif source $OCAB/activate $CONDA_DESIRED_ENV; then
    echo "- New environment: $CONDA_DEFAULT_ENV ($CONDA_PREFIX)"
    echo "- New path: $PATH"

else
    echo "- Activation of environment $CONDA_DESIRED_ENV failed"
fi

if ! which R; then
    echo "- R not found; activating fallback environment"
    source $OCAB/activate $CONDA_FALLBACK_ENV
    echo "- New environment: $CONDA_DEFAULT_ENV ($CONDA_PREFIX)"
    echo "- New path: $PATH"
fi

# Update the R_HOME-based environment variables
if [ "$OLD_PFX" != "$CONDA_PREFIX" ]; then
    echo "- pointing environment variables to the new environment"
    vars=$(env | sed -nE "/^CONDA/!s@$OLD_PFX/@$CONDA_PREFIX/@p")
    while read -r line; do
        declare -x $line
    done <<< "$vars"

    echo "- Writing new conda environment variables"
    env | grep ^CONDA > ~/.Renviron
    echo PATH=$PATH >> ~/.Renviron
fi

# Add CONDA_DESIRED_ENV to ~/.Renviron so .Rprofile sees it
echo CONDA_DESIRED_ENV=$CONDA_DESIRED_ENV >> ~/.Renviron

# We need $CONDA_PREFIX/lib in LD_LIBRARY_PATH
# $CONDA_PREFIX/lib/R/lib is already in there
export LD_LIBRARY_PATH=$CONDA_PREFIX/lib:$LD_LIBRARY_PATH
echo "- Executing rsession with arguments: $@"
exec /usr/lib/rstudio-server/bin/rsession "$@"
