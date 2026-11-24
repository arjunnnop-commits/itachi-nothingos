#!/data/data/com.termux/files/usr/bin/sh
# Phone-only helper: pushes this folder to YOUR (empty, private) GitHub repo so Actions can build the binaries.
# Termux: pkg install git ; create an empty repo + a fine-grained token (Contents: read/write) on github.com first.
# Usage: GH_USER=you GH_REPO=itachi-duchamp GH_TOKEN=xxxx sh tools/push_to_github.sh
set -e
: "${GH_USER:?set GH_USER}" "${GH_REPO:?set GH_REPO}" "${GH_TOKEN:?set GH_TOKEN}"
cd "$(dirname "$0")/.."
git init -q -b main 2>/dev/null || git init -q
git config user.name "$GH_USER"
git config user.email "$GH_USER@users.noreply.github.com"
git add -A
git commit -qm "itachi-duchamp port" || true
git remote remove origin 2>/dev/null || true
git remote add origin "https://$GH_USER:$GH_TOKEN@github.com/$GH_USER/$GH_REPO.git"
git push -u origin main --force
git remote set-url origin "https://github.com/$GH_USER/$GH_REPO.git"
echo "Pushed. Open github.com/$GH_USER/$GH_REPO -> Actions -> build-itachi-duchamp -> Run workflow."
