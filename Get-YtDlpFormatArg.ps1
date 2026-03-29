function Get-YtDlpFormatArg {
    param ([string]$Cmd)
    switch ($Cmd) {
        "/max" { return "bestvideo+bestaudio/best" }
        "/1080p" { return "bestvideo[height<=1080]+bestaudio/best[height<=1080]" }
        "/audio" { return "bestaudio/best" }
        Default { return "bestvideo[height<=1080]+bestaudio/best[height<=1080]" }
    }
}
