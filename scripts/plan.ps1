# Only local preparation and read-only AWS/Terraform operations are permitted.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("staging", "prod")]
    [string]$Environment
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path -Parent $PSScriptRoot
$terraformRoot = Join-Path $projectRoot ("infra/environments/" + $Environment)
$localDir = Join-Path $projectRoot '.local'
New-Item -ItemType Directory -Force $localDir | Out-Null
$credentialVars = @('AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_SESSION_TOKEN', 'AWS_SECURITY_TOKEN', 'AWS_PROFILE', 'AWS_DEFAULT_PROFILE', 'AWS_REGION', 'AWS_DEFAULT_REGION', 'AWS_ROLE_ARN', 'AWS_WEB_IDENTITY_TOKEN_FILE', 'AWS_CONTAINER_CREDENTIALS_RELATIVE_URI', 'AWS_CONTAINER_CREDENTIALS_FULL_URI', 'AWS_ENDPOINT_URL', 'AWS_ENDPOINT_URL_STS', 'AWS_ENDPOINT_URL_EC2', 'TF_CLI_ARGS', 'TF_CLI_ARGS_plan')
$previous = @{}
try {
    foreach ($name in $credentialVars) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    $env:AWS_PROFILE = 'poc-personal'
    $env:AWS_DEFAULT_PROFILE = 'poc-personal'
    $env:AWS_REGION = 'us-west-2'
    $env:AWS_DEFAULT_REGION = 'us-west-2'
    $identityText = & aws sts get-caller-identity --profile poc-personal --region us-west-2 --output json --no-cli-pager
    if ($LASTEXITCODE -ne 0) { throw 'STS identity verification failed.' }
    $identity = $identityText | ConvertFrom-Json
    if ($identity.Account -ne '495278513214') { throw 'Wrong account. Planning stopped.' }
    Write-Output "Verified profile poc-personal; account $($identity.Account)."
    & terraform "-chdir=$terraformRoot" init -input=false
    if ($LASTEXITCODE -ne 0) { throw 'Terraform init failed.' }
    & terraform "-chdir=$terraformRoot" validate
    if ($LASTEXITCODE -ne 0) { throw 'Terraform validate failed.' }
    & terraform "-chdir=$terraformRoot" plan -input=false -lock-timeout=30s -out="$localDir/$Environment.tfplan" -detailed-exitcode
    if ($LASTEXITCODE -notin @(0, 2)) { throw 'Terraform plan failed.' }
    Write-Output 'Plan complete. No apply or cloud mutation was performed.'
    # Terraform detailed-exitcode 2 means a successful plan with changes.
    $global:LASTEXITCODE = 0
} finally {
    foreach ($name in $previous.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
    }
}
