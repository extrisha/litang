[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    $RemainingArgs
)

$nodeScript = Join-Path $PSScriptRoot "build_apk.mjs"
& node $nodeScript @RemainingArgs
exit $LASTEXITCODE
