import os
import sys
try:
    import ruamel_yaml as yaml
except ImportError:
    import yaml
from glob import glob
from os.path import dirname, basename, join

PROJECT_DIR = sys.argv[1]
ENVS_DIRS = [
    '/opt/continuum/.conda/envs',
    '/opt/continuum/envs',
    '/opt/continuum/anaconda/envs'
]

def _intif(x):
    try:
        return int(x)
    except:
        return 0

r_envs = []
r_versions = {}
all_envs = set()
for ebase in ENVS_DIRS:
    g_envs = []
    for emeta in glob(join(ebase, '*', 'conda-meta')):
        epath = dirname(emeta)
        ename = basename(epath)
        if ename in all_envs:
            ename = epath
        all_envs.add(ename)
        for pkg in glob(join(emeta, 'r-base-*.json')):
            r_versions[ename] = basename(pkg).split('-', 3)[2]
            ver = tuple(map(_intif, r_versions[ename].split('.')))
            g_envs.append((ver, ename))
    r_envs.extend(v for k, v in sorted(g_envs, reverse=True))

# This function is likely overkill but it is shared with
# ae5-rstudio and ae5-vscode so we're offering the more
# comprehensive search for safety (and it's cheap)

def _ordered_environment_set(pdir):
    env_names = []
    def _add(x):
        if x and x not in env_names:
            env_names.append(x)
    try:
        from anaconda_project.project_info import publication_info
        spec = publication_info(pdir)
        for cspec in spec.get('commands', {}).values():
            _add(cspec.get('env_spec'))
        for ename in spec.get('env_specs', {}).keys():
            _add(ename)
    except Exception:
    except Exception as exc:
        print('Could not parse pixi.toml/anaconda-project.yml.', file=sys.stderr)
    root = os.environ.get('CONDA_ROOT')
    if sys.prefix != root:
        _add(sys.prefix)
    _add('base')
    return env_names

results = _ordered_environment_set(PROJECT_DIR)
desired_env = results[0]
results = [r for r in results if r in r_envs]
if results:
    active_env = results[0]
elif os.environ.get('CONDA_DEFAULT_ENV') in r_envs:
    active_env = os.environ['CONDA_DEFAULT_ENV']
elif r_envs:
    active_env = next(iter(r_envs))
else:
    active_env = desired_env
print(desired_env, active_env, r_versions[active_env])
