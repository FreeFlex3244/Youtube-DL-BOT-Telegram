[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$BotToken,
    [Parameter(Mandatory=$false)]
    [string]$SecurityToken
)

# Configuration & Initialization
$ErrorActionPreference = "Stop"
$WorkingDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($WorkingDir)) {
    $WorkingDir = (Get-Location).Path
}

$ToolsDir = Join-Path -Path $WorkingDir -ChildPath "tools"
$DownloadsDir = Join-Path -Path $WorkingDir -ChildPath "downloads"
$DataDir = Join-Path -Path $WorkingDir -ChildPath "data"

if (!(Test-Path -Path $ToolsDir)) { New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null }
if (!(Test-Path -Path $DownloadsDir)) { New-Item -ItemType Directory -Path $DownloadsDir -Force | Out-Null }
if (!(Test-Path -Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }

$YtDlpPath = Join-Path -Path $ToolsDir -ChildPath "yt-dlp.exe"
$FfmpegPath = Join-Path -Path $ToolsDir -ChildPath "ffmpeg.exe"
$FfprobePath = Join-Path -Path $ToolsDir -ChildPath "ffprobe.exe"
$AuthorizedUsersFile = Join-Path -Path $DataDir -ChildPath "authorized_users.json"

function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$Timestamp] $Message"
}

# Dependency Download Logic
if (!(Test-Path -Path $YtDlpPath)) {
    Write-Log "yt-dlp.exe introuvable. Telechargement en cours... / Descarregant yt-dlp.exe..."
    $YtDlpUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
    Invoke-WebRequest -Uri $YtDlpUrl -OutFile $YtDlpPath
    Write-Log "yt-dlp.exe telecharge. / yt-dlp.exe descarregat."
}

if (!(Test-Path -Path $FfmpegPath) -or !(Test-Path -Path $FfprobePath)) {
    Write-Log "ffmpeg/ffprobe introuvables. Telechargement en cours... / Descarregant ffmpeg/ffprobe..."
    $FfmpegZipUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
    $TempZip = Join-Path -Path $ToolsDir -ChildPath "ffmpeg.zip"
    Invoke-WebRequest -Uri $FfmpegZipUrl -OutFile $TempZip
    Write-Log "Extraction de ffmpeg... / Extreient ffmpeg..."
    Expand-Archive -Path $TempZip -DestinationPath $ToolsDir -Force

    $ExtractedFolder = Get-ChildItem -Path $ToolsDir -Directory -Filter "ffmpeg-*-essentials_build" | Select-Object -First 1
    if ($ExtractedFolder) {
        $BinDir = Join-Path -Path $ExtractedFolder.FullName -ChildPath "bin"
        Copy-Item -Path (Join-Path -Path $BinDir -ChildPath "ffmpeg.exe") -Destination $ToolsDir -Force
        Copy-Item -Path (Join-Path -Path $BinDir -ChildPath "ffprobe.exe") -Destination $ToolsDir -Force
        Remove-Item -Path $ExtractedFolder.FullName -Recurse -Force
    }
    if (Test-Path $TempZip) { Remove-Item -Path $TempZip -Force }
    Write-Log "ffmpeg installe. / ffmpeg instal·lat."
}

# Request tokens if not provided
if ([string]::IsNullOrEmpty($BotToken)) {
    $BotToken = Read-Host "Veuillez entrer le Token du Bot Telegram / Si us plau, introdueix el Token del Bot de Telegram"
}
if ([string]::IsNullOrEmpty($SecurityToken)) {
    $SecurityToken = Read-Host "Veuillez definir un mot de passe (Token) de securite pour les utilisateurs / Defineix una contrasenya de seguretat"
}

# --- Telegram API Helpers ---
$TelegramApiUrl = "https://api.telegram.org/bot$BotToken"

function Send-TelegramMessage {
    param (
        [string]$ChatId,
        [string]$Text
    )
    $Url = "$TelegramApiUrl/sendMessage"
    $Body = @{
        chat_id = $ChatId
        text = $Text
    } | ConvertTo-Json
    $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    try {
        Invoke-RestMethod -Uri $Url -Method Post -ContentType "application/json; charset=utf-8" -Body $BodyBytes | Out-Null
    } catch {
        Write-Log "Erreur envoi message / Error enviant missatge: $_"
    }
}

function Send-TelegramFile {
    param (
        [string]$ChatId,
        [string]$FilePath,
        [string]$Type = "document" # video, audio, document
    )

    if (!(Test-Path $FilePath)) {
        Write-Log "Fichier introuvable / Fitxer no trobat: $FilePath"
        return
    }

    $FileInfo = Get-Item $FilePath
    if ($FileInfo.Length -gt 50MB) {
        Send-TelegramMessage -ChatId $ChatId -Text "⚠️ Fichier trop volumineux (>50MB) pour etre envoye par Telegram (limite de bot) / Fitxer massa gran (>50MB).`nTaille / Mida: $([math]::Round($FileInfo.Length / 1MB, 2)) MB"
        return
    }

    Write-Log "Envoi du fichier / Enviant fitxer: $FilePath"
    $Url = "$TelegramApiUrl/send$Type"

    # Using curl.exe for multipart/form-data upload which is built-in Windows 10+
    $CurlArgs = @(
        "-s",
        "-X", "POST",
        $Url,
        "-F", "chat_id=$ChatId",
        "-F", "$Type=@$FilePath"
    )

    $Result = & curl.exe $CurlArgs 2>&1
    Write-Log "Resultat curl: $Result"
}

$ProcessDownloadBlock = {
    param(
        [string]$ChatId,
        [string]$Command,
        [string]$Url,
        [bool]$IsPlaylist,
        [string]$DownloadsDir,
        [string]$ToolsDir,
        [string]$YtDlpPath,
        [string]$TelegramApiUrl,
        [string]$GetYtDlpFormatArgPath
    )

    if (Test-Path $GetYtDlpFormatArgPath) {
        . $GetYtDlpFormatArgPath
    }

    function Write-Log {
        param([string]$Message)
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$Timestamp] $Message"
    }

    function Send-TelegramMessage {
        param ([string]$ChatId, [string]$Text)
        $UrlApi = "$TelegramApiUrl/sendMessage"
        $Body = @{ chat_id = $ChatId; text = $Text } | ConvertTo-Json
        $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
        try { Invoke-RestMethod -Uri $UrlApi -Method Post -ContentType "application/json; charset=utf-8" -Body $BodyBytes | Out-Null } catch { Write-Log "Erreur envoi message : $_" }
    }

    function Send-TelegramFile {
        param ([string]$ChatId, [string]$FilePath, [string]$Type = "document")
        if (!(Test-Path $FilePath)) { return }
        $FileInfo = Get-Item $FilePath
        if ($FileInfo.Length -gt 50MB) {
            Send-TelegramMessage -ChatId $ChatId -Text "⚠️ Fichier trop volumineux (>50MB) pour etre envoye par Telegram / Fitxer massa gran.`nTaille / Mida: $([math]::Round($FileInfo.Length / 1MB, 2)) MB"
            return
        }
        $UrlApi = "$TelegramApiUrl/send$Type"
        $CurlArgs = @("-s", "-X", "POST", $UrlApi, "-F", "chat_id=$ChatId", "-F", "$Type=@$FilePath")
        & curl.exe $CurlArgs 2>&1 | Out-Null
    }

    $Format = Get-YtDlpFormatArg -Cmd $Command
    $OutputTemplate = Join-Path -Path $DownloadsDir -ChildPath "%(title)s.%(ext)s"

    $YtArgs = @($Url, "--format", $Format, "--merge-output-format", "mp4", "--ffmpeg-location", $ToolsDir, "--output", $OutputTemplate, "--no-warnings")

    if ($Command -eq "/audio") {
        $YtArgs += "--extract-audio"
        $YtArgs += "--audio-format"
        $YtArgs += "mp3"
    }

    if ($IsPlaylist) { $YtArgs += "--yes-playlist" } else { $YtArgs += "--no-playlist" }

    Send-TelegramMessage -ChatId $ChatId -Text "⏳ Telechargement en cours... / Descarregant...`nLien / Enllac: $Url"

    $BeforeFiles = @(Get-ChildItem -Path $DownloadsDir | Select-Object -ExpandProperty FullName)

    $Process = Start-Process -FilePath $YtDlpPath -ArgumentList $YtArgs -NoNewWindow -Wait -PassThru

    if ($Process.ExitCode -eq 0) {
        $AfterFiles = @(Get-ChildItem -Path $DownloadsDir | Select-Object -ExpandProperty FullName)
        $NewFiles = Compare-Object -ReferenceObject $BeforeFiles -DifferenceObject $AfterFiles | Where-Object {$_.SideIndicator -eq "=>"} | Select-Object -ExpandProperty InputObject

        if ($null -ne $NewFiles) {
            foreach ($File in $NewFiles) {
                Send-TelegramMessage -ChatId $ChatId -Text "✅ Fichier telecharge! Envoi en cours... / Fitxer descarregat! Enviant..."
                $Type = "document"
                if ($File -match "\.mp4$") { $Type = "video" } elseif ($File -match "\.mp3$") { $Type = "audio" }
                Send-TelegramFile -ChatId $ChatId -FilePath $File -Type $Type
                Remove-Item -Path $File -Force -ErrorAction SilentlyContinue
            }
        } else {
            Send-TelegramMessage -ChatId $ChatId -Text "❌ Le telechargement a reussi, mais aucun nouveau fichier trouve / Descarrega completada pero no s'ha trobat el fitxer."
        }
    } else {
        Send-TelegramMessage -ChatId $ChatId -Text "❌ Erreur lors du telechargement / Error durant la descarrega. Verifiez le lien / Comproveu l'enllac."
    }
}

# Process-Download function is removed in favor of $ProcessDownloadBlock


# --- Authorized Users Management ---
[string[]]$global:AuthorizedUsers = @()
if (Test-Path $AuthorizedUsersFile) {
    try {
        $Content = Get-Content -Path $AuthorizedUsersFile -Raw
        if (![string]::IsNullOrWhiteSpace($Content)) {
            $Parsed = $Content | ConvertFrom-Json
            if ($null -ne $Parsed) {
                # Force array casting
                $global:AuthorizedUsers = [string[]]@($Parsed)
            }
        }
    } catch {
        Write-Log "Erreur lecture authorized_users.json: $_"
    }
}

function Add-AuthorizedUser {
    param([string]$ChatId)
    if ($ChatId -notin $global:AuthorizedUsers) {
        $global:AuthorizedUsers += $ChatId
        # Force array preservation when converting to JSON
        @($global:AuthorizedUsers) | ConvertTo-Json | Set-Content -Path $AuthorizedUsersFile
        Write-Log "Nouvel utilisateur autorise : $ChatId"
    }
}

# --- Polling Loop ---
Write-Log "Bot initialise. Pret. / Bot inicialitzat. Llest."
$Offset = 0
$JobCleanupCounter = 0

while ($true) {
    # Job Cleanup
    $JobCleanupCounter++
    if ($JobCleanupCounter -ge 10) {
        Get-Job -State Completed | Remove-Job -Force -ErrorAction SilentlyContinue
        $JobCleanupCounter = 0
    }
    try {
        $Url = "$TelegramApiUrl/getUpdates?offset=$Offset&timeout=30"
        $Response = Invoke-RestMethod -Uri $Url -Method Get -TimeoutSec 60

        if ($Response.ok -and $Response.result.Count -gt 0) {
            foreach ($Update in $Response.result) {
                $Offset = $Update.update_id + 1

                if ($null -ne $Update.message -and $null -ne $Update.message.text) {
                    $ChatId = $Update.message.chat.id.ToString()
                    $Text = $Update.message.text.Trim()

                    Write-Log "Message recu ($ChatId): $Text"

                    # Verification securite
                    if ($ChatId -notin $global:AuthorizedUsers) {
                        if ($Text -eq $SecurityToken) {
                            Add-AuthorizedUser -ChatId $ChatId
                            Send-TelegramMessage -ChatId $ChatId -Text "✅ Authentification reussie! Bienvenue. / Autenticacio correcta! Benvingut.`nCommandes:`n/max <url> - Qualite max`n/1080p <url> - 1080p max`n/audio <url> - Audio mp3`n/playlist <url> - Playlist"
                        } else {
                            Send-TelegramMessage -ChatId $ChatId -Text "❌ Non autorise. Veuillez envoyer le Token secret. / No autoritzat. Si us plau, envieu el Token secret."
                        }
                        continue
                    }

                    # --- Command Handling ---
                    if ($Text -eq "/start" -or $Text -eq "/help") {
                         Send-TelegramMessage -ChatId $ChatId -Text "👋 Bonjour! / Hola!`n`nCommandes:`n/max <url> - Video qualite maximum`n/1080p <url> - Video en 1080p maximum`n/audio <url> - Fichier audio seul`n/playlist <url> - Telecharger playlist (1080p par defaut)"
                    } elseif ($Text -match "^/(max|1080p|audio|playlist)\s+(http.+)") {
                        $Command = "/$($Matches[1])"
                        $UrlTarget = $Matches[2]
                        $IsPlaylist = ($Command -eq "/playlist")

                        # Process asynchronous download to unblock polling loop
                        $JobArgs = @(
                            $ChatId,
                            (if($IsPlaylist) { "/1080p" } else { $Command }),
                            $UrlTarget,
                            $IsPlaylist,
                            $DownloadsDir,
                            $ToolsDir,
                            $YtDlpPath,
                            $TelegramApiUrl,
                            (Join-Path -Path $WorkingDir -ChildPath "Get-YtDlpFormatArg.ps1")
                        )
                        Write-Log "Execution command: $Command $UrlTarget"
                        Start-Job -ScriptBlock $ProcessDownloadBlock -ArgumentList $JobArgs | Out-Null
                    } else {
                        Send-TelegramMessage -ChatId $ChatId -Text "⚠️ Commande non reconnue ou lien manquant. / Comanda no reconeguda o falta l'enllac.`nEx: /1080p https://youtube.com/..."
                    }
                }
            }
        }
    } catch {
        Write-Log "Erreur de connexion a Telegram / Error connectant a Telegram: $_"
        Start-Sleep -Seconds 5
    }
}
