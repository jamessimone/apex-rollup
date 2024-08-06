git config --local user.email "action@github.com"
git config --local user.name "GitHub Action Bot"
git commit -m "Bumping package version from Github Action" --no-verify
git push

# Once the commit has been uploaded to Github, we need to callout
# to have the commit status set to success - otherwise the PR checks
# won't show up as having been cleared correctly

latestSha=$(git rev-parse HEAD)

curl \
  -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/$GITHUB_REPOSITORY/statuses/$latestSha \
  -d '{"state":"success", "description": "Build success!", "context": "scratch-org-test"}'