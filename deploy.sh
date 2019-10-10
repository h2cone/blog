#!/bin/sh
# https://gohugo.io/hosting-and-deployment/hosting-on-github/

# If a command fails then the deploy stops
set -e

rm -rf public

printf "\033[0;32mDeploying updates to GitHub...\033[0m\n"

# Build the project.
hugo -t even

# Go To Public folder
cd public

# Add changes to git.
git init
git add .

# Commit changes.
msg="rebuilding site $(date)"
if [ -n "$*" ]; then
	msg="$*"
fi
git commit -m "$msg"

# Push source and build repos.
git push -f git@github.com:h2cone/h2cone.github.io.git master

cd ..