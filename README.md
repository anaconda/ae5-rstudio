# Adding RStudio support to AE5

This repository allows AE5 customers to install RStudio into the AE5
editor container and use it within AE5. In order to ensure respect for
RStudio Server's licensing terms, Anaconda does not provide the RStudio
binary to customers; they must acquire it themselves. These instructions
are intended to be followed by the customer as well, and can be applied
to AE 5.3.x or later. 

When successfully completed, RStudio will be made available as an editor
selection in AE's dropdown menus alongside Jupyter, JupyterLab, and Zeppelin.

Installation is a three step process that introduces minimal
disruption to a running cluster. If necessary, the cluster can be reverted
to the stock behavior, without RStudio, also with minimal disruption.

## Installation

The installation steps are as follows. Step 1 can be performed on
a flexible schedule, while Steps 2 and 3 should be performed in rapid
succession with notification delivered to users.

1. _*Build the Docker image.*_
   - Time to complete: less than an hour
   - User disruption: none. This step only _stages_ the modified Docker
     image for use. Existing sessions are uninterrupted, and new sessions
     continue to use the stock images.
2. _*Modify the deployment to point to the new image.*_
   - Time to complete: <5 minutes
   - User disruption: none for existing sessions, deployments, or jobs.
     Creation of new sessions, as well as creation of new projects
     from templates, samples, and uploads, will be disrupted for
     approximately 1-2 minutes while the workspace pod restarts.
     Once the workspace pod is fully operational again, and until
     step 3 is completed, users should discern no functional
     difference in operation.
3. _*Update the Postgres database to include an RStudio option.*_
   - Time to complete: <5 minutes
   - User disruption: none for existing sessions, deployments, or jobs.
     Once the database is updated, the RStudio option will appear for
     new and/or restarted sessions. Some users may need to refresh their
     browsers to pick up the new option.

### Step 1. Build the Docker image

As stated above, the Docker image can be built without disruption of the
cluster. That is because the steps in this section only create a new Docker
image and stage it for _later_ use. Because the image is
built upon the existing one, the disk space required to hold
the new image will be minimal.

1. Log into the master node using an account with `sudo`/`gravity` access.
2. Create a directory visible within Gravity; e.g., `/opt/anaconda/rstudio`
3. Copy the contents of this repository to this directory.
4. By default, the build process will download the RStudio-Server RPM package from
   the following URL:
   ```
   https://download2.rstudio.org/server/centos6/x86_64/rstudio-server-rhel-1.2.1335-x86_64.rpm
   ```
   In a firewalled/airgapped environment, this may not be possible. If this is
   the case, download this file manually and deliver it to the same directory as
   step 1, alongside the `Dockerfile` itself.
5. Enter the Gravity environment, and change to the same directory.
   ```
   sudo gravity enter
   cd /opt/anaconda/rstudio
   ```
6. Determine the name of the current editor image.
   ```
   WORKSPACE=$(kubectl get pods | grep ap-workspace- | \
               awk '{print $1;}' | xargs kubectl describe pod | \
               grep ANACONDA_PLATFORM_IMAGES_EDITOR | awk '{print $2;}')
   echo $WORKSPACE
   ```
7. Build the new image and push it to the internal registry. Before we
   run the `docker build` command we need to set the `FROM` statement
   to match the value of WORKSPACE above, hence the `sed` command. You
   could also edit the Dockerfile by hand if you wish.
   ```
   sed -i "s@^FROM .*@FROM $WORKSPACE@" Dockerfile
   docker build --build-arg WORKSPACE=$WORKSPACE -t $WORKSPACE-rstudio .
   docker push $WORKSPACE-rstudio
   ```
   By design, the name of the image is identical to the original, but with
   an `-rstudio` suffix appended to the tag. This simplifies the
   deployment editing steps below.

  Note: For this to work on AE 5.4GA (5.4.0-40.gbd07dc6fb) the fallback environment needs to change from anaconda50_r to anaconda44_r
  ``` pushd ae5-rstudio && sed -i s/anaconda50_r/anaconda44_r/ *.sh && popd```
     
8. Exit the Gravity environment.

### 2. Modify the deployment to point to the new image

1. Edit the deployment for the workspace container.
   ```
   kubectl edit deploy anaconda-enterprise-ap-workspace
   ```
2. Search for the line containing `name: ANACONDA_PLATFORM_IMAGES_EDITOR`.
   In a standard installation, this should be approximately line 60.
3. Add the `-rstudio` suffix to the `value:` on the _next line_
4. Save and exit the editor.

The workspace pod will automatically restart. Users will not be able to
launch new editor sessions, or create new projects, for approximately 1-2
minutes. When the workspace pod finishes initializing, they should be
able to create projects and sessions as usual. RStudio will _not_ be
functional yet, and the first new sessions created on each worker node
may take a bit longer to start as the additional image layers are retrieved.

To verify that the new image is being utilized, launch a session and verify
that the following files/directories are present:
- `/opt/continuum/.Rprofile`
- `/opt/continuum/scripts/start_rstudio.sh`
- `/opt/continuum/scripts/rsession.sh`
- `/usr/lib/rstudio-server/`

### 3. Update the Postgres database to include the RStudio option

The editor drop-down is fed from a single cell in an underlying
postgres database, which is itself running as a Kubernetes pod.
1. Determine the exact name of the Postgres pod.
   ```
   POSTGRES=$(kubectl get pods | grep -e -postgres- | cut -f 1 -d ' ')
   echo $POSTGRES
   ```
2. Copy `workspace-new.json` into the container and launch a shell.
   ```
   kubectl cp workspace-new.json $POSTGRES:/
   kubectl exec -it $POSTGRES /bin/sh
   ```
   At this point, you are running a shell inside the Postgres pod,
   and steps 3-6 will be performed inside that pod.
3. Examine the current value of the editor list.
   ```
   psql -U postgres -d anaconda_ui -c \
       "select options from integration where name='workspace';"
   ```
   The contents should closely resemble the contents of the file `workspace-orig.json`.
4. Modify the editor list using the contents of the file `workspace-new.json`.
   ```
   VALUE=$(cat workspace-new.json)
   psql -U postgres -d anaconda_ui -c \
       "update integration set options='$VALUE' where name='workspace';"
   ```
   You should expect an output of `UPDATE 1`.
5. Re-run Step 3 and confirm that RStudio is indeed present
   in the editor list.
6. Type `exit` to leave the Postgres container shell.

Once you have successfully completed Step 3, all new attempts to use the
drop-down editor list will see RStudio present.

## Uninstallation

If it is necessary to remove RStudio, we effectively reverse the steps above.

1. _Update the Postgres database to remove the RStudio option._
   - Time to complete: <5 minutes
   - User disruption: none for existing sessions, deployments, or jobs.
     Once the database is updated, the RStudio option will no longer
     appear for new and/or restarted sessions. Some users may need to
     refresh their browsers for the RStudio option to disappear.
2. _Modify the deployment to point to the original image._
   - Time to complete: <5 minutes
   - User disruption: none for existing sessions, deployments, or jobs.
     Creation of new sessions, as well as creation of new projects
     from templates, samples, and uploads, will be disrupted for
     approximately 1-2 minutes while the workspace pod restarts.
     Once the workspace pod is fully operational again, and until
     step 3 is completed, users should discern no functional
     difference in operation if they were not using RStudio previously.
     RStudio users _may_ need to modify their project settings to
     select an editor besides RStudio.
3. _Optionally remove the custom Docker image._
   - Time to complete: varies; must wait for all users to stop using
     the custom Docker image, or force their sessions to be stopped.
   - User disruption: none, unless there is a need to force a session
     stoppage to remove the image.

### 1. Update the Postgres database to remove the RStudio option

1. Determine the exact name of the Postgres pod.
   ```
   POSTGRES=$(kubectl get pods | grep -e -postgres- | cut -f 1 -d ' ')
   echo $POSTGRES
   ```
2. Copy `workspace-orig.json` into the container and launch a shell.
   ```
   kubectl cp workspace-orig.json $POSTGRES:/
   kubectl exec -it $POSTGRES /bin/sh
   ```
   At this point, you are running a shell inside the Postgres pod,
   and steps 3-5 will be run inside that pod.
3. Modify the editor list using the contents of `workspace-new.json`.
   ```
   VALUE=$(cat workspace-orig.json)
   echo $VALUE # and confirm it is not empty
   psql -U postgres -d anaconda_ui -c \
       "update integration set options='$VALUE' where name='workspace';"
   ```
   You should expect an output of `UPDATE 1`.
4. Examine the new editor list to confirm that RStudio has been removed:
   ```
   psql -U postgres -d anaconda_ui -c \
       "select options from integration where name='workspace';"
   ```
5. Type `exit` to leave the Postgres container shell.

These changes should take effect once this step is complete:
- All existing sessions, including those with RStudio, will continue
  to run without change.
- The "Default Editor" drop-down on the project Settings page will
  no longer list RStudio as an option.
- _Existing RStudio projects_ will continue to start with RStudio.
  The "Default Editor" field may appear blank, however.

### 2. Revert the workspace deployment 

1. Edit the deployment for the workspace container.
   ```
   kubectl edit deploy anaconda-enterprise-ap-workspace
   ```
2. Search for the line containing `name: ANACONDA_PLATFORM_IMAGES_EDITOR`.
   In a standard installation, this should be approximately line 60.
3. _Remove_ the `-rstudio` suffix to the `value:` on the _next line_
4. Save and exit the editor.

Once these steps are complete, tworkspace pod will automatically restart.
Users will not be able to launch new editor sessions, or create new
projects, for approximately 1-2 minutes. When the workspace pod finishes
initializing, the following changes should take effect:
- Users should be able to create projects and start sessions.
- Existing sessions, including those running RStudio, will continue to function.
- _New_ and _restarted_ sessions for projects with RStudio as the
  selected editor will _fail_. To resolve this, the session must be
  stopped, and an alternate editor selected and saved.

### 3. Optionally remove the custom Docker image

The RStudio image does not consume a significant amount of additional
disk space, and is therefore likely not to pose a problem if it is simply
left in the Docker registry. However, if you do wish to remove the image
completely, you can, _once it is no longer being used_. In particular it
is not sufficient that there are no users using RStudio; even users of
JupyterLab, Jupyter, and Zeppelin may be using the custom image.

1. Scan the existing pods to see if any are using the RStudio image.
   ```
   kubectl get pods \
       -o=jsonpath='{range .items[*]}{"\n"}{.metadata.name}{":"}{range .spec.containers[*]}{.image}{","}{end}{end}{"\n"}' \
       | sed -nE 's@([^:]+):.*-rstudio.*@\1@p'
   ```
   If this search produces an empty result, then there are no sessions that
   use an RStudio-enabled container. If there are any sessions, you must
   wait for them to be restarted before proceeding.
2. Enter the gravity environment.
   ```
   sudo gravity enter
   ```
3. Recall the name of the standard editor image.
   ```
   WORKSPACE=$(kubectl get pods | grep ap-workspace- | \
               awk '{print $1;}' | xargs kubectl describe pod | \
               grep ANACONDA_PLATFORM_IMAGES_EDITOR | awk '{print $2;}')
   echo $WORKSPACE
   ```
4. Remove the customized image.
   ```
   docker image rm $WORKSPACE-rstudio
   ```
5. Exit gravity.

As with the image creation step, this should not result in any user disruption,
particular since it cannot be completed until all users must first have ceased
using the custom image.
