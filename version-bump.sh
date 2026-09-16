#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: version-bump.sh [--dry-run]

Compare origin/master RSTUDIO_VERSION to the Open Source RStudio Server
RHEL 9/10 RPM on https://docs.posit.co/ide/user/ and open, update, or
close the single bot/rstudio-version PR as needed.

  --dry-run   Report the action that would be taken; do not create,
              close, or modify a PR, and do not commit or push.
EOF
}

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "Unknown argument: $arg" >&2
            usage >&2
            exit 1
            ;;
    esac
done

extract_version() {
    sed -n 's/.*|| RSTUDIO_VERSION=\([0-9]\{4\}\.[0-9]\{2\}\.[0-9][0-9]*-[0-9][0-9]*\).*/\1/p' | head -n 1
}

version_le() {
    local IFS='.-'
    local a=($1) b=($2)
    local i ai bi
    for i in 0 1 2 3; do
        ai=${a[$i]:-0}
        bi=${b[$i]:-0}
        if ((10#$ai < 10#$bi)); then return 0; fi
        if ((10#$ai > 10#$bi)); then return 1; fi
    done
    return 0
}

owner="${GITHUB_REPOSITORY_OWNER:-}"
if [ -z "$owner" ]; then
    origin_url=$(git remote get-url origin)
    owner=$(printf '%s\n' "$origin_url" | sed -n 's/.*github.com[:/]\([^/]*\)\/.*/\1/p')
fi
if [ -z "$owner" ]; then
    echo "Could not determine GitHub repository owner" >&2
    exit 1
fi

html=$(curl -fsSL https://docs.posit.co/ide/user/)
matches=$(printf '%s\n' "$html" | grep -oE 'https://download2\.rstudio\.org/server/rhel9/x86_64/rstudio-server-rhel-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-x86_64\.rpm' | sort -u || true)
if [ -z "$matches" ]; then
    echo "Expected exactly one RHEL 9/10 server RPM link, found 0" >&2
    exit 1
fi
count=$(printf '%s\n' "$matches" | wc -l)
if [ "$count" -ne 1 ]; then
    echo "Expected exactly one RHEL 9/10 server RPM link, found $count" >&2
    printf '%s\n' "$matches" >&2
    exit 1
fi
upstream=$(printf '%s\n' "$matches" | sed -n 's/.*rstudio-server-rhel-\([0-9.]*-[0-9]*\)-x86_64\.rpm/\1/p')
if ! [[ "$upstream" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]+-[0-9]+$ ]]; then
    echo "Upstream version '$upstream' does not match YYYY.MM.N-N" >&2
    exit 1
fi
echo "Upstream (docs RHEL 9/10): $upstream"

git fetch origin master
git fetch origin bot/rstudio-version:refs/remotes/origin/bot/rstudio-version 2>/dev/null || true

master_ver=$(git show origin/master:download_rstudio.sh | extract_version)
if [ -z "$master_ver" ]; then
    echo "Could not read RSTUDIO_VERSION from origin/master" >&2
    exit 1
fi
echo "master RSTUDIO_VERSION: $master_ver"

pr_number=$(gh pr list --head "${owner}:bot/rstudio-version" --state open --json number --jq '.[0].number // empty')
pr_ver=
if [ -n "$pr_number" ]; then
    if git rev-parse --verify origin/bot/rstudio-version >/dev/null 2>&1; then
        pr_ver=$(git show origin/bot/rstudio-version:download_rstudio.sh | extract_version)
    fi
    echo "Open bump PR #$pr_number version: ${pr_ver:-unknown}"
fi

close_pr() {
    local reason=$1
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "DRY-RUN: would close PR #$pr_number: $reason"
        pr_number=
        pr_ver=
        return
    fi
    echo "Closing PR #$pr_number: $reason"
    gh pr close "$pr_number" --comment "$reason"
    pr_number=
    pr_ver=
}

write_pr_body() {
    printf '%s\n' \
        'Automated RStudio Server version bump.' \
        '' \
        "- Source: https://docs.posit.co/ide/user/#rstudio-server-oss-downloads (RHEL 9 / 10)" \
        "- \`RSTUDIO_VERSION\`: \`${master_ver}\` → \`${upstream}\`" \
        '' \
        'Main CI will run `download_rstudio.sh` against this version.' \
        > /tmp/pr-body.md
}

if [ -n "$pr_number" ] && [ -n "$pr_ver" ] && version_le "$pr_ver" "$master_ver"; then
    close_pr "master already has ${master_ver}, which is the same as or newer than this PR (${pr_ver}). Closing."
fi

if version_le "$upstream" "$master_ver"; then
    if [ -n "$pr_number" ]; then
        close_pr "master already has ${master_ver} ≥ upstream ${upstream}. Closing this bump PR."
    else
        echo "No bump needed: upstream ${upstream} ≤ master ${master_ver}"
    fi
    exit 0
fi

if [ -n "$pr_number" ] && [ "$pr_ver" = "$upstream" ]; then
    echo "Open PR #$pr_number already pins $upstream"
    exit 0
fi

title="chore: bump RSTUDIO_VERSION to ${upstream}"
if [ "$DRY_RUN" -eq 1 ]; then
    if [ -n "$pr_number" ]; then
        echo "DRY-RUN: would update PR #$pr_number: ${pr_ver:-unknown} → ${upstream}"
    else
        echo "DRY-RUN: would create PR '$title' (${master_ver} → ${upstream})"
    fi
    exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git checkout --no-track -B bot/rstudio-version origin/master
sed -i.bak -e "s/|| RSTUDIO_VERSION=[0-9]\{4\}\.[0-9]\{2\}\.[0-9][0-9]*-[0-9][0-9]*/|| RSTUDIO_VERSION=${upstream}/" download_rstudio.sh
rm -f download_rstudio.sh.bak
new_ver=$(extract_version < download_rstudio.sh)
if [ "$new_ver" != "$upstream" ]; then
    echo "Failed to bump RSTUDIO_VERSION to $upstream (got '${new_ver:-empty}')" >&2
    exit 1
fi
if git diff --quiet download_rstudio.sh; then
    echo "No change after bump; unexpected" >&2
    exit 1
fi

printf 'chore: bump RSTUDIO_VERSION to %s\n' "$upstream" > /tmp/commit-msg.txt
git add download_rstudio.sh
git commit -F /tmp/commit-msg.txt
git push --force origin bot/rstudio-version

write_pr_body
if [ -n "$pr_number" ]; then
    gh pr edit "$pr_number" --title "$title" --body-file /tmp/pr-body.md
    echo "Updated PR #$pr_number"
else
    gh pr create --base master --head bot/rstudio-version --title "$title" --body-file /tmp/pr-body.md
fi
