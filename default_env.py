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

results = []
try:
    with open(join(PROJECT_DIR, 'anaconda-project.yml'), 'r') as fp:
        envs = yaml.safe_load(fp).get('env_specs')
    if not envs or 'default' in envs:
        results.append('default')
    results.extend(e for e in envs if e != 'default')
except Exception as exc:
    results.append('@ERROR@')
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
