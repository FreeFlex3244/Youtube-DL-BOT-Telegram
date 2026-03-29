# Get-YtDlpFormatArg.Tests.ps1
$ScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "..\Get-YtDlpFormatArg.ps1"
. $ScriptPath

Describe "Get-YtDlpFormatArg" {
    It "returns bestvideo+bestaudio/best for /max command" {
        $result = Get-YtDlpFormatArg -Cmd "/max"
        $result | Should -Be "bestvideo+bestaudio/best"
    }

    It "returns 1080p limited format for /1080p command" {
        $result = Get-YtDlpFormatArg -Cmd "/1080p"
        $result | Should -Be "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
    }

    It "returns bestaudio/best for /audio command" {
        $result = Get-YtDlpFormatArg -Cmd "/audio"
        $result | Should -Be "bestaudio/best"
    }

    It "returns 1080p limited format for unknown commands (Default case)" {
        $result = Get-YtDlpFormatArg -Cmd "/unknown"
        $result | Should -Be "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
    }

    It "returns 1080p limited format for empty command (Default case)" {
        $result = Get-YtDlpFormatArg -Cmd ""
        $result | Should -Be "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
    }
}
