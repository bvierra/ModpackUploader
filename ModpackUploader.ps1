. .\settings.ps1

$downloadUrl = @{}
$downloadUrl['7z'] = 'https://www.7-zip.org/a/7z1900-x64.exe'

$CWD=Get-Location
$BinPath="$CWD\.bin"


function Get-PreReqs {
    if(!(Test-Path $BinPath)) {
        New-Item -ItemType Directory -Force -Path $BinPath
    }

    <#
     # Required no matter what options are set 
     #>

    # Java
    if (!(Get-Command "java.exe" -ErrorAction SilentlyContinue)) {
        throw 'Could not locate java.exe in your $env:Path. Aborting!'
    }

    # Curl
    # TODO - Download and install to $BinPath
    if (!(Get-Command "curl.exe" -ErrorAction SilentlyContinue)) {
        throw 'Could not locate curl.exe in your $env:Path. Aborting!'
    }

    # 7-Zip
    if (Get-Command "7z.exe" -ErrorAction SilentlyContinue) {
        # Checks current $end:Path for 7z.exe and uses it if found
        Set-Alias sz "7z.exe"
    } elseif (test-path "$env:ProgramFiles\7-Zip\7z.exe") {
        # Checks ProgramFiles and uses it if found
        Set-Alias sz "$env:ProgramFiles\7-Zip\7z.exe"
    } else {
        # Could not find so download from 7-zip.org and place in $BinPath
        Write-Host "Could not find 7z.exe in your path or at $env:ProgramFiles\7-Zip\7z.exe"
        Write-Host "Downloading it now and placing it in $BinPath"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest $downloadUrl['7z'] -Out $BinPath\7z.exe -ErrorAction Stop
        Set-Alias sz "$BinPath\7z.exe"
    }

    # TwitchExportBuilder (if enabled)
    if ($ENABLE_MANIFEST_BUILDER_MODULE) {
        $TwitchExportBuilder = "TwitchExportBuilder.exe"
        if (!(Test-Path $BinPath\$TwitchExportBuilder) -or $ENABLE_ALWAYS_UPDATE_JARS) {
            Remove-Item $BinPath\$TwitchExportBuilder -Recurse -Force -ErrorAction SilentlyContinue
            Get-GithubRelease -repo "Gaz492/twitch-export-builder" -file "twitch-export-builder_windows_amd64.exe"
            Move-Item -Path ".\twitch-export-builder_windows_amd64.exe" -Destination "$BinPath\$TwitchExportBuilder" -ErrorAction SilentlyContinue
        }
    }

    # Changelog Generator
    if ($ENABLE_CHANGELOG_GENERATOR_MODULE -and $ENABLE_MODPACK_UPLOADER_MODULE) {
        $ChangelogGenerator = "ChangelogGenerator.jar"
        if (!(Test-Path $BinPath\$ChangelogGenerator) -or $ENABLE_ALWAYS_UPDATE_JARS) {
            Remove-Item $BinPath\$ChangelogGenerator -Recurse -Force -ErrorAction SilentlyContinue
            Get-GithubRelease -repo "TheRandomLabs/ChangelogGenerator" -file $ChangelogGenerator
            Rename-Item -Path $ChangelogGenerator -Destination "$BinPath\$ChangelogGenerator" -ErrorAction SilentlyContinue
        }
    }

}

function Get-GithubRelease {
    
    param(
        [parameter(Mandatory=$true)]
        [string]
        $repo,
        [parameter(Mandatory=$true)]
        [string]
        $file
    )
	
    $releases = "https://api.github.com/repos/$repo/releases"

    Write-Host "Determining latest release of $repo"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $tag = (Invoke-WebRequest -Uri $releases -UseBasicParsing | ConvertFrom-Json)[0].tag_name

    $download = "https://github.com/$repo/releases/download/$tag/$file"
    $name = $file.Split(".")[0]

    Write-Host Downloading $download to $file...
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest $download -Out $file

    # Cleaning up target dir
    Remove-Item $name -Recurse -Force -ErrorAction SilentlyContinue
}

function Clear-SleepHost {
    Start-Sleep 2
    Clear-Host
}

Get-PreReqs

if ($ENABLE_MANIFEST_BUILDER_MODULE) {
    & "$BinPath\TwitchExportBuilder.exe" -n "$CLIENT_FILENAME" -p "$MODPACK_VERSION"
    Clear-SleepHost
}

if ($ENABLE_CHANGELOG_GENERATOR_MODULE -and $ENABLE_MODPACK_UPLOADER_MODULE) {
    Remove-Item oldmanifest.json, manifest.json, shortchangelog.txt, MOD_CHANGELOGS.txt -ErrorAction SilentlyContinue
    sz e "$CLIENT_FILENAME`-$LAST_MODPACK_VERSION.zip" manifest.json
    Rename-Item -Path manifest.json -NewName oldmanifest.json
    sz e "$CLIENT_FILENAME`-$MODPACK_VERSION.zip" manifest.json

    Clear-SleepHost
    Write-Host "######################################" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Generating changelog..." -ForegroundColor Green
    Write-Host ""

    java -jar "$BinPath\ChangelogGenerator.jar" oldmanifest.json manifest.json
    Rename-Item -Path changelog.txt -NewName MOD_CHANGELOGS.txt
}

if ($ENABLE_GITHUB_CHANGELOG_GENERATOR_MODULE) {

    $BASE64TOKEN = [System.Convert]::ToBase64String([char[]]$GITHUB_TOKEN);
    $Uri = "https://api.github.com/repos/$GITHUB_NAME/$GITHUB_REPOSITORY/releases?access_token=$GITHUB_TOKEN"

    $Headers = @{
        Authorization = 'Basic {0}' -f $Base64Token;
    };

    $Body = @{
        tag_name = $MODPACK_VERSION;
        target_commitish = 'master';
        name = $MODPACK_VERSION;
        body = $CLIENT_CHANGELOG;
        draft = $false;
        prerelease = $false;
    } | ConvertTo-Json;

    Clear-SleepHost
    if ($ENABLE_EXTRA_LOGGING) {
        Write-Host "Release Data:"
        Write-Host $Body 
    }

    Write-Host ""
    Write-Host "######################################" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Making GitHub Release..." -ForegroundColor Green
    Write-Host ""

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-RestMethod -Headers $Headers -Uri $Uri -Body $Body -Method Post

	Start-Process Powershell.exe -Argument "-NoProfile -Command github_changelog_generator --since-tag $CHANGES_SINCE_VERSION"
}

if ($ENABLE_MODPACK_UPLOADER_MODULE) {
    $CLIENT_FILENAME = "$CLIENT_FILENAME-$MODPACK_VERSION.zip"

    $CLIENT_METADATA = 
    "{
    'changelog': `'$CLIENT_CHANGELOG`',
    'changelogType': `'$CLIENT_CHANGELOG_TYPE`',
    'displayName': `'$CLIENT_FILE_DISPLAY_NAME`',
    'gameVersions': [$GAME_VERSIONS],
    'releaseType': `'$CLIENT_RELEASE_TYPE`'
    }"
    
    Clear-SleepHost
    if ($ENABLE_EXTRA_LOGGING) {
        Write-Host "Client Metadata:"
        Write-Host $CLIENT_METADATA 
    }

    Write-Host ""
    Write-Host "######################################" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uploading client files..." -ForegroundColor Green
    Write-Host ""

    $Response = curl.exe --url "https://minecraft.curseforge.com/api/projects/$CURSEFORGE_PROJECT_ID/upload-file" --user "$CURSEFORGE_USER`:$CURSEFORGE_TOKEN" -H "Accept: application/json" -H X-Api-Token:$CURSEFORGE_TOKEN -F metadata=$CLIENT_METADATA -F file=@$CLIENT_FILENAME --progress-bar | ConvertFrom-Json
    $ResponseId = $Response.id

    Write-Host ""
    Write-Host "######################################" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "The modpack has been uploaded." -ForegroundColor Green
    Write-Host "ID returned: $ResponseId" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "######################################" -ForegroundColor Cyan
    Write-Host ""
    Start-Sleep -Seconds 1
}

if ($ENABLE_SERVER_FILE_MODULE -and $ENABLE_MODPACK_UPLOADER_MODULE) {
    Clear-SleepHost
    Write-Host ""
    Write-Host "######################################" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Compressing Server files..." -ForegroundColor Green
    Write-Host ""
    Write-Host "######################################" -ForegroundColor Cyan
    Write-Host ""

    $SERVER_FILENAME = "$SERVER_FILENAME.zip"
    sz a -tzip $SERVER_FILENAME $CONTENTS_TO_ZIP

    $SERVER_METADATA = 
    "{
    'changelog': `'$SERVER_CHANGELOG`',
    'changelogType': `'$SERVER_CHANGELOG_TYPE`',
    'displayName': `'$SERVER_FILE_DISPLAY_NAME`',
    'parentFileId': $ResponseId,
    'releaseType': `'$SERVER_RELEASE_TYPE`'
    }"

    Clear-SleepHost
    if ($ENABLE_EXTRA_LOGGING) {
        Write-Host "Server Metadata:"
        Write-Host $SERVER_METADATA
    }

    Write-Host ""
    Write-Host "######################################" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Uploading server files..." -ForegroundColor Green
    Write-Host ""

    $ResponseServer = curl.exe --url "https://minecraft.curseforge.com/api/projects/$CURSEFORGE_PROJECT_ID/upload-file" --user "$CURSEFORGE_USER`:$CURSEFORGE_TOKEN" -H "Accept: application/json" -H X-Api-Token:$CURSEFORGE_TOKEN -F metadata=$SERVER_METADATA -F file=@$SERVER_FILENAME --progress-bar
    $ResponseServerId = $ResponseServer.id

    Write-Host ""
    Write-Host "######################################" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "The modpack server files have been uploaded." -ForegroundColor Green
    Write-Host "ID returned: $ResponseServerId" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "######################################" -ForegroundColor Cyan
    Write-Host ""
    Start-Sleep -Seconds 1
}

Clear-SleepHost

Write-Host "######################################" -ForegroundColor Cyan
Write-Host ""
Write-Host "The Modpack Uploader has completed." -ForegroundColor Green
Write-Host ""
Write-Host "######################################" -ForegroundColor Cyan

Start-Sleep -Seconds 5