param(
    [string]$Organization
)

if ($Organization -notmatch '^https?://dev.azure.com/\w+') {
    $Organization = "https://dev.azure.com/$Organization"
}

# Make sure we are signed in to Azure
$AccountInfo = az account show 2>&1
try {
    $AccountInfo = $AccountInfo | ConvertFrom-Json -ErrorAction Stop
}
catch {
    az login --allow-no-subscriptions
}

# Make sure we have Azure DevOps extension installed
$DevOpsExtension = az extension list --query '[?name == ''azure-devops''].name' -o tsv
if ($null -eq $DevOpsExtension) {
    $null = az extension add --name 'azure-devops'
}

$Projects = az devops project list --organization $Organization --query 'value[].name' -o tsv
foreach ($Proj in $Projects) {
    if (-not (Test-Path -Path ".\$Proj" -PathType Container)) {
        New-Item -Path $Proj -ItemType Directory |
        Select-Object -ExpandProperty FullName |
        Push-Location
    }
    Push-Location 
    $Repos = az repos list --organization $Organization --project $Proj | ConvertFrom-Json
    foreach ($Repo in $Repos) {
        if(-not (Test-Path -Path $Repo.name -PathType Container)) {
            Write-Warning -Message "Cloning repo $Proj\$($Repo.Name)"
            git clone $Repo.webUrl
        }
        # Navigate into the cloned repository directory
        Push-Location $Repo.name

        # Run gitleaks detect and append results to gitleaks-results.txt
        Write-Host "Running gitleaks detect on $Proj\$($Repo.Name)"
        gitleaks detect -s . -v >> gitleaks-results.txt
        echo "###################################" >> gitleaks-results.txt

        $linesCount = Get-ChildItem -Recurse | Where-Object { -not $_.PSIsContainer } | Get-Content | Measure-Object -Line
        Write-Host "Lines count in $Proj\$($Repo.Name): $($linesCount.Lines)"
        
        # Return to the parent directory
        Pop-Location
    }
}