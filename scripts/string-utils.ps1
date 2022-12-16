$ErrorActionPreference = 'Stop'

function Get-Current-Git-Branch() {
  Invoke-Expression 'git rev-parse --abbrev-ref HEAD'
}

function Find-And-Replace-Content() {
  param(
    $path,
    $searchString,
    $replacement
  )
  $content = Get-Content -Raw -Path $path
  $targetRegEx = "(.+$searchString = ')(.+)(';)"
  $replacementRegEx = '${1}' + $replacement + '${3}'
  $content -replace $targetRegEx, $replacementRegEx | Set-Content -Path $path -NoNewline
}