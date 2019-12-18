FROM leader.telekube.local:5000/ae-editor:5.3.1-22.g6cafcc9c5
COPY . /aesrc/rstudio/
RUN set -ex \
    && cd /aesrc/rstudio \
    && if [[ ! -f rstudio-server-rhel-1.2.1335-x86_64.rpm ]] ; then curl -O https://download2.rstudio.org/server/centos6/x86_64/rstudio-server-rhel-1.2.1335-x86_64.rpm ; fi \
    && if [[ ! -f psmisc-22.20-16.el7.x86_64.rpm ]] ; then  curl -O https://rpmfind.net/linux/centos/7.7.1908/os/x86_64/Packages/psmisc-22.20-16.el7.x86_64.rpm ; fi \
    && if [[ ! $(rpm  -qa | grep psmisc) ]]; then rpm -i psmisc-22.20-16.el7.x86_64.rpm ; fi \
    && if [[ ! $(rpm -qa | grep rstudio-server) ]]; then rpm -i rstudio-server-rhel-1.2.1335-x86_64.rpm ;fi \
    && rm -rf rstudio-server-rhel-1.2.1335-x86_64.rpm \
    && rm -rf psmisc-22.20-16.el7.x86_64.rpm \
    && cp Rprofile /opt/continuum/.Rprofile \
    && if [ ! -f /opt/continuum/scripts/start_user.sh ]; then cp startup.sh build_condarc.py run_tool.py /opt/continuum/scripts/; fi \
    && cp rsession.sh start_rstudio.sh /opt/continuum/scripts/ \
    && chmod +x /opt/continuum/scripts/*.sh \
    && chown anaconda:anaconda /opt/continuum/scripts/*.sh
