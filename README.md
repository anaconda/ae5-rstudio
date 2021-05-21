# Adding RStudio support to AE5.5

This repository allows AE5 customers to install RStudio and use it within
AE5.5.  In order to ensure respect for RStudio Server's licensing terms,
Anaconda does not provide the RStudio binary to customers; they must acquire
it themselves. These instructions are intended to be followed by the customer
and can be applied to AE 5.5 or later.

When successfully completed, RStudio will be made available as an editor
selection in AE's dropdown menus alongside Jupyter, JupyterLab, and Zeppelin.

Installation is a three step process that introduces minimal disruption to a
running cluster. If necessary, the cluster can be reverted to the stock behavior,
without RStudio, also with minimal disruption.

## Installation

The installation steps are as follows. Step 1 can be performed on
a flexible schedule, while Steps 2 and 3 should be performed in rapid
succession with notification delivered to users.

1. _*Build the Docker image.*_
   - Time to complete: less than an hour, not including optional preparation
     time to design the optional default environment.
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
3. _*Modify the UI configuration to include an RStudio option.*_
   - Time to complete: <5 minutes
   - User disruption: none for existing sessions, deployments, or jobs.
     Because the UI pod is restarted, users may experience a brief
     disruption in UI responsiveness for 1-2 minutes.

### Step 1. Build the Docker image

As stated above, the Docker image can be built without disruption of the
cluster. That is because the steps in this section only create a new Docker
image and stage it for _later_ use. Because the image is
built upon the existing one, the disk space required to hold
the new image will be minimal.

1. Log into the master node using an account with `sudo`/`gravity` access.
2. Create a directory visible within Gravity; e.g., `/opt/anaconda/rstudio`
3. Copy the `Dockerfile` in this repository into that directory.
4. In addition, we need the two files found at the following URLs:

   - `https://download2.rstudio.org/server/centos8/x86_64/rstudio-server-rhel-1.3.959-x86_64.rpm`
   - `https://download2.rstudio.org/server/centos6/x86_64/rstudio-server-rhel-1.3.959-x86_64.rpm`

   Note that the filenames here are identical, but they are different files.
   For this reason, our Dockerfile expects the downloaded copies of these files
   to be named `r8.rpm` and `r6.rpm`, respectively. The following pair of `curl`
   commands ensure they are downloaded properly and staged for our build:
   ```
   curl -o r8.rpm -L https://download2.rstudio.org/server/centos8/x86_64/rstudio-server-rhel-1.3.959-x86_64.rpm
   curl -o r6.rpm -L https://download2.rstudio.org/server/centos6/x86_64/rstudio-server-rhel-1.3.959-x86_64.rpm
   ```
4. Enter the Gravity environment, and change to the same directory.
   ```
   sudo gravity enter
   cd /opt/anaconda/rstudio
   ```
5. Determine the name of the current editor image.
   ```
   IMAGENAME=$(docker image ls | grep ae-editor | grep -v rstudio | grep 5.5 | awk '{print $1":"$2;}')
   echo $IMAGENAME
   ```
   Make sure this image name makes sense. It should look something like this:
   ```
   leader.telekube.local:5000/ae-editor:5.5.0-58-g403cc503d
   ```
   but the version number may be different.
6. Build the new image and push it to the internal registry. Before we
   run the `docker build` command we need to set the `FROM` statement
   to match the value of IMAGENAME above, hence the `sed` command. You
   could also edit the Dockerfile by hand if you wish.
   ```
   sed -i "s@^FROM .*@FROM $IMAGENAME@" Dockerfile
   docker build --build-arg IMAGENAME=$IMAGENAME -t $IMAGENAME-rstudio .
   docker push $IMAGENAME-rstudio
   ```
   By design, the name of the image is identical to the original, but with
   an `-rstudio` suffix appended to the tag. This simplifies the
   deployment editing steps below.
7. Run the command
   ```
   docker image ls | grep $IMAGENAME-rstudio
   ```
   to verify that the image that was just created is visible.
8. Exit the Gravity environment.

### 2. Modify the workspace pod to point to the new image

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
that there is content in the directory `/usr/lib/rstudio-server/`.

### 3. Update the UI configuration to incude the RStudio option

The final step is to add RStudio to the editor selection list presented
by the UI.
1. Launch a web browser, log into the Op Center, and navigate to
   the "Configuration" tab.
2. Make sure that the "Config maps" dropdown has selected the
   `anaconda-enterprirse-anaconda-platform.yml` option. This should
   be the default. You will see a single tab titled `anaconda-platform.yml`;
   this is file to be edited.
3. Search for the `anaconda-workspace:` section of this file. The quickest way to do so
   is to focus the text editor and search for `anaconda-workspace:` (including the colon).
   The default values in this section will look like this:
   ```   
    anaconda-workspace:
      workspace:
        icon: fa-anaconda
        label: workspace
        url: http://anaconda-enterprise-ap-workspace
        options:
          workspace:
            tools:
              notebook:
                default: true
                label: Jupyter Notebook
              jupyterlab:
                default: false
                label: JupyterLab
              zeppelin:
                default: false
                label: Apache Zeppelin
   ```
4. Add an RStudio section, so that the section looks as follows.
   _It is essential that exact indentation, with spaces, is preserved._
   ```
    anaconda-workspace:
      workspace:
        icon: fa-anaconda
        label: workspace
        url: http://anaconda-enterprise-ap-workspace
        options:
          workspace:
            tools:
              notebook:
                default: true
                label: Jupyter Notebook
              jupyterlab:
                default: false
                label: JupyterLab
              zeppelin:
                default: false
                label: Apache Zeppelin
              rstudio:
                default: false
                hidden: false
                label: RStudio
   ```
   _NOTE:_ if your configuration already has an `rstudio` section, simply
   make sure that the value of the `hidden:` parameter is `false:`.
5. Once you have verified the correct formatting, click the "Save Changes" button.
6. Return to the master node and restart the UI pod.
   ```
   kubectl get pods | grep anaconda-enterprise-ap-ui | \
       cut -f 1 -d ' ' | xargs kubectl delete pods
   ```
   The UI pod should take less than a minute to refresh.

There may be minor disruptions in UI responsiveness during this time, and
some users may need to refresh their browsers, although this should not be
necessary for views of running sessions or deployments. Once the refresh
is complete, the RStudio editor will be present in the Default Editor
drop-down on the project settings page.

To help clarify the desired result in this step, we have attached below
a screenshot of the Op Center for a typical cluster immediately
after Step 5 is completed.

![screenshot](screenshot.png)

## Uninstallation

If it is necessary to remove RStudio, we effectively reverse the steps above.

1. _*Modify the UI configuration to remove the RStudio option.*_
   - Time to complete: <5 minutes
   - User disruption: none for existing sessions, deployments, or jobs.
     Because the UI pod is restarted, users may experience a brief
     disruption in UI responsiveness for 1-2 minutes.
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

### 1. Modify the UI configuration to remove the RStudio option

The first step in uninstallation is to remove the RStudio option from the UI.
1. Launch a web browser, log into the Op Center, and navigate to
   the "Configuration" tab.
2. Make sure that the "Config maps" dropdown has selected the
   `anaconda-enterprirse-anaconda-platform.yml` option. This should
   be the default. You will see a single tab titled `anaconda-platform.yml`;
   this is file to be edited.
3. Search for the three-line `rstudio:` section of this file, and change the
   line `hidden: false` to `hidden: true`. Do not change the indentation.
4. Click the "Save Changes" button.
5. Log into the master node and restart the UI pod.
   ```
   kubectl get pods | grep anaconda-enterprise-ap-ui | \
       cut -f 1 -d ' ' | xargs kubectl delete pods
   ```
   The UI pod should take less than a minute to refresh.

As before, there may be minor disruptions in UI responsiveness while the
pod is being restarted. Some users may need to refresh their browsers,
although this should not be necessary for views of running
sessions or deployments. These changes should take effect
once this step is complete:
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
   IMAGENAME=$(docker image ls | grep ae-editor.*rstudio | awk '{print $1":"$2;}')
   echo $IMAGENAME
   ```
4. Remove the customized image.
   ```
   docker image rm $IMAGENAME
   ```
5. Exit gravity.

As with the image creation step, this should not result in any user disruption,
particular since it cannot be completed until all users must first have ceased
using the custom image.
