.First = function() {
  wait_for_prepare_log <- function(newSession) {
    readRenviron('/opt/continuum/.Renviron')
    current_env = Sys.getenv('CONDA_DEFAULT_ENV')
    desired_env = Sys.getenv('CONDA_DESIRED_ENV')
    fpath = '/opt/continuum/prepare.log'
    if (!file.exists(fpath)) {
      if (current_env == desired_env) {
        message('NOTE: The project environment is still being prepared.')
        message('If you do not wish to wait, press RETURN then ESC to exit to')
        message('the command line; but note that some R packages may not yet')
        message('be available for use until this process is complete.')
      } else {
        message('Requested conda environment: ', desired_env)
        message('NOTE: The requested environment is still being created. Once')
        message('this is complete, R will be restarted. If you do not wish to')
        message('wait, press RETURN then ESC to exit to the command line; but')
        message('note that you will then need to monitor the creation process')
        message('yourself, and restart R manually when it is complete.')
      }
      counter = 0
      cat('Waiting...')
      while (!file.exists(fpath)) {
          Sys.sleep(0.2)
          counter = counter + 1
          if (counter == 15) {
              counter = 0
              cat('.')
              flush.console()
          }
      }
      cat('\n')
      message('Environment preparation is complete.')
      if (current_env != desired_env) {
        message('Restarting R...')
        .rs.api.restartSession()
      }
    } else if (Sys.getenv('CONDA_PROJECT_ERR') == 'yes') {
      message('ERROR: an unexpected error prevented the startup script')
      message('from determining the desired conda environment. This is')
      message('typically caused by corruption in anaconda-project.yml.')
      message('Consult the file /opt/continuum/prepare.log for details.')
    } else if (current_env != desired_env) {
      message('Requested conda environment: ', desired_env)
      message('ERROR: The project preparation stage is complete, but the')
      message('requested conda environment does not have an R interpreter.')
      message('This is either because the anaconda-project.yml file does')
      message('not specify an r-base package, or there was an error during')
      message('preparation. Consult the file /opt/continuum/prepare.log')
      message('for more details.')
    }
  }
  if (Sys.getenv("RSTUDIO") == "1") {
    setHook("rstudio.sessionInit", wait_for_prepare_log, action="append")
  }
}
cat('Active conda environment:', Sys.getenv('CONDA_DEFAULT_ENV'), '\n')
