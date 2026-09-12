<#
===============================================================================
 WOODVILLE PC & TECH - WOODVILLE PC TOOLKIT v11.4
 Portable Windows diagnostic, repair, maintenance and technician toolkit.

 PowerShell compatibility: Windows PowerShell 5.1 minimum.
 No external PowerShell modules are required.

 Design goals:
   - Offline-first
   - Evidence before repair
   - Safe-by-default
   - WhatIf is a true no-change mode
   - No silent reboot
   - No silent driver installation (SDIO always hands off to its own GUI)
   - Missing optional tools are reported as NotInstalled/NotAvailable
   - Persistent state for safe resume
   - Structured results + JSON/CSV/HTML reporting
   - Portable paths based on $PSScriptRoot

 v11.4 changes:
   - Added a WPF GUI (-Gui): sidebar navigation (Dashboard/Workflows, Windows Tweaks,
     Application Catalog, Technician Tools, Reports, Settings), one-click workflow
     bundles, and a live-tailing log panel. Architecture note: the GUI never runs
     repair/install/tweak logic in-process - every action launches a fresh -Unattended
     subprocess of this exact script (inheriting the GUI's own elevation, no second UAC
     prompt) and tails its log file. This was a deliberate choice over sharing mutable
     state across threads, which is far easier to get subtly wrong in code that can't be
     tested against a real Windows/WPF session.
   - Added a small, real Sophia-style reversible tweak architecture (Get/Set/Restore) for
     5 well-understood registry tweaks (file extensions, hidden files, taskbar search mode,
     Task View button, consumer features/suggestions) - NOT a port of Sophia's much larger
     catalog. Every Apply saves a snapshot; Restore reapplies the last saved value.
     Available via -ApplyTweaks/-RestoreTweaks or the GUI's Windows Tweaks page.
   - Fixed: ConvertTo-ElevationArguments was a hardcoded switch list despite the project
     spec explicitly requiring generic $PSBoundParameters-based forwarding - meaning every
     new parameter (like this release's -Gui) would have silently failed to survive an
     elevation relaunch unless someone remembered to add it here by hand. Now genuinely
     generic; also fixed the subtler issue that $PSBoundParameters is scoped per-function
     in PowerShell, so the fix required capturing it explicitly at the script's top level
     into $script:AllBoundParameters rather than just referencing $PSBoundParameters
     inside the called function (which would have silently seen an empty set instead).
   - NOT implemented from the accompanying 43-section spec (listed here rather than
     silently dropped): health scoring, BSOD/Reliability Monitor correlation, live
     CPU/RAM/disk telemetry dashboard, SMART/NVMe/thermal hardware diagnostics beyond what
     Storage/Hardware stages already collect, full reboot-resume state machine, duplicate
     file analyzer, event-log clustering, a declarative feature-registry that dynamically
     builds GUI pages, and Sophia's/WinUtil's full tweak and app catalogs. Each is a real,
     separately-scoped effort; building them unverified in one pass would produce
     plausible-looking code with no way to confirm it actually works.

 v11.3 changes:
   - Added a curated Application Catalog (Config\AppCatalog.json) with real winget IDs
     sourced from ChrisTitusTech/winutil's applications.json - reachable interactively via
     the main menu or -Stage AppCatalog. Selection IS the authorization; nothing installs
     without the technician picking it, and it never runs under -Unattended.
   - Fixed: HTML report's finding-count cards used "@(...)" inside a double-quoted
     here-string, which is not a valid interpolation trigger - it printed literal
     PowerShell text instead of a number. Now precomputed and inserted with "$(...)".
   - Fixed: -Stage TechTools was accepted by validation but had no dispatch case,
     so it silently did nothing. Now wired to the Technician Tool Center (skipped
     automatically if -Unattended, since it's interactive).
   - Fixed: driver backup could fail because pnputil's export folder didn't exist yet.
   - Fixed: Get-Counter can throw a terminating error on machines with corrupted
     performance counters - now caught and logged as a finding instead of failing the run.
   - Fixed: New-Result's -ExitCode was typed [int] with a $null default, which silently
     became 0 - indistinguishable from a real "exit code 0" success. Now stays $null.
   - Completed: Drivers/WindowsUpdate/Debloat previously only *detected* SDIO, WSUS
     Offline, and debloat candidates - the Safety.AllowDriverInstall /
     Safety.AllowWindowsUpdateRepair / Safety.AllowDebloatChanges config flags existed
     but were never actually checked anywhere. They now gate real execution (all
     default to false, so behavior is unchanged until a technician opts in via
     Config\Toolkit.json).
   - Report branding (company name/tagline/logo) now actually reads from
     Config\Toolkit.json instead of being hardcoded text in the HTML template.
===============================================================================

===============================================================================
 ATTRIBUTIONS / THIRD-PARTY LICENSES
===============================================================================
 Config\AppCatalog.json's default entries (application names, categories, and
 winget package IDs) are derived from ChrisTitusTech/winutil:
     https://github.com/ChrisTitusTech/winutil
 winutil is MIT licensed. Per the MIT license, its copyright and permission
 notice must be preserved wherever its content is reused:

     MIT License
     Copyright (c) Chris Titus Tech and winutil contributors
     Permission is hereby granted, free of charge, to any person obtaining a
     copy of this software and associated documentation files, to deal in the
     software without restriction, including without limitation the rights to
     use, copy, modify, merge, publish, distribute, sublicense, and/or sell
     copies of the software, subject to including the above copyright notice
     and this permission notice in all copies or substantial portions.
     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

 This is a curated subset (~35 entries) selected and re-typed for repair-shop
 relevance, not a verbatim copy of winutil's ~1800-line catalog - but the
 winget IDs themselves originated from that project, so the notice applies.

 The Windows Tweaks feature (Get/Set/Restore pattern) was independently
 implemented in this script. It follows the same architectural PATTERN used
 by farag2/Sophia-Script-for-Windows (https://github.com/farag2/Sophia-Script-for-Windows,
 MIT licensed) but contains no code copied from that project - the actual
 registry paths/values for the 5 tweaks implemented here were determined
 independently, not transcribed from Sophia's source.
===============================================================================

===============================================================================
 TESTING STATUS - READ BEFORE DEPLOYING TO A CLIENT MACHINE
===============================================================================
 No part of this script has been executed in a real Windows/PowerShell/WPF
 session. There is no Windows environment available in the sandbox this was
 written in - only static analysis was possible. Per-change, what "static
 analysis" actually means here:

   STATICALLY VERIFIED (checked, but NOT the same as tested):
     - Brace/paren/bracket balance across the whole file
     - Here-string delimiter pairing (@"/"@ and @'/'@)
     - The embedded GUI XAML parses as well-formed XML
     - Every stage in Get-StageOrder has a matching Get-StageAction case, and
       vice versa (except TechTools/AppCatalog, intentionally interactive-only)
     - Every function referenced from stage dispatch/GUI code-behind exists
       elsewhere in the file
     - Parameter names/signatures cross-checked at each call site (e.g.
       New-Result, Add-Change, Add-Result) against their definitions

   REQUIRES WINDOWS TEST (not verified in any way - could contain bugs):
     - That the GUI actually renders and lays out as intended
     - That WPF event handlers fire correctly and closures capture the right
       values (especially the per-iteration GetNewClosure() usage)
     - Every external tool invocation (DISM, SFC, pnputil, wevtutil, bcdedit,
       netsh, winget, SDIO, WSUS Offline) - argument syntax, exit-code meaning,
       and output parsing are all based on documentation/prior knowledge, not
       a live run
     - Registry tweak values on an actual Windows 10/11 install
     - Elevation relaunch and argument-forwarding round-trip
     - Any timing-sensitive behavior (log tailing, process exit detection)

 Test on a disposable VM before running against a customer's machine. Start
 with -WhatIf, then individual -Stage runs, before -Full or -Gui.
===============================================================================
#>

[CmdletBinding()]
param(
    [ValidateSet('Preflight','Audit','Backup','Hardware','Storage','Security','EventLogs',
                 'Performance','Repair','Cleanup','Network','Drivers','WindowsUpdate',
                 'Debloat','Applications','AppCatalog','WindowsConfig','Restore','TechTools',
                 'RebootResume','Verification','Finalize','FinalReport','All')]
    [string[]]$Stage = @(),

    [switch]$WhatIf,
    [switch]$Unattended,
    [switch]$Help,
    [switch]$Gui,
    [switch]$SkipBackup,
    [switch]$SkipRepair,
    [switch]$SkipCleanup,
    [switch]$SkipMalware,
    [switch]$OfflineMode,
    [switch]$NoReboot,

    [string[]]$InstallApps,
    [string[]]$ApplyTweaks,
    [string[]]$RestoreTweaks,

    [string]$ConfigPath,
    [string]$ClientName,
    [string]$TicketNumber,
    [string]$TechName,
    [string]$ReportedIssue,
    [ValidateSet('Debug','Info','Warning','Error')]
    [string]$LogLevel = 'Info'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'
$WarningPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# $PSBoundParameters is scoped per-function in PowerShell - a function called later that
# bare-references $PSBoundParameters sees its OWN (empty) bound parameters, not the
# script's. Capturing it explicitly here is what makes generic forwarding in
# ConvertTo-ElevationArguments actually work.
$script:AllBoundParameters = $PSBoundParameters

$script:Toolkit = @{
    Name       = 'WoodvillePCToolkit'
    Version    = '11.4'
    Company    = 'Woodville PC & Tech'
    ScriptPath = $PSScriptRoot
    ScriptName = [IO.Path]::GetFileName($PSCommandPath)
    PowerShell = $PSVersionTable.PSVersion.ToString()
}

$script:RunId = ([guid]::NewGuid()).ToString()
$script:StartUtc = (Get-Date).ToUniversalTime()
$script:Paths = @{}
$script:Config = @{}
$script:State = @{}
$script:Results = New-Object System.Collections.ArrayList
$script:Findings = New-Object System.Collections.ArrayList
$script:Artifacts = New-Object System.Collections.ArrayList
$script:Changes = New-Object System.Collections.ArrayList
$script:Backups = New-Object System.Collections.ArrayList
$script:TranscriptWriter = $null
$script:PreviousStateDetected = $false
$script:RebootRequired = $false
$script:OverallStatus = 'HEALTHY WITH WARNINGS'

# Embedded fallback logo (used unless Config\Toolkit.json's LogoPath points at a real file).
$script:DefaultLogoBase64 = @'
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
'@

function Get-UtcString {
    return (Get-Date).ToUniversalTime().ToString('o')
}

function Test-IsAdministrator {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function ConvertTo-JsonSafe {
    param([object]$InputObject)
    try {
        return ($InputObject | ConvertTo-Json -Depth 12)
    } catch {
        return ($InputObject | Out-String)
    }
}

function Write-AtomicText {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $tmp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($tmp, $Content, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

function Initialize-Paths {
    $root = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = Split-Path -Parent $PSCommandPath
    }
    if ([string]::IsNullOrWhiteSpace($root)) {
        throw 'Unable to determine toolkit root.'
    }

    $script:Paths = @{
        Root       = $root
        Config     = Join-Path $root 'Config'
        Backups    = Join-Path $root 'Backups'
        Logs       = Join-Path $root 'Logs'
        Reports    = Join-Path $root 'Reports'
        Cache      = Join-Path $root 'Cache'
        Binaries   = Join-Path $root 'Binaries'
        Tools      = Join-Path $root 'Tools'
        State      = Join-Path $root 'State'
        SDIO       = Join-Path $root 'sdio2'
        WSUS       = Join-Path $root 'wsusoffline'
    }

    foreach ($p in $script:Paths.GetEnumerator()) {
        if ($p.Key -ne 'Root' -and -not (Test-Path -LiteralPath $p.Value)) {
            New-Item -ItemType Directory -Path $p.Value -Force | Out-Null
        }
    }
}

function Test-SafeToolkitPath {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [switch]$MustExist
    )
    try {
        $full = [IO.Path]::GetFullPath($Path)
        $root = [IO.Path]::GetFullPath($script:Paths.Root).TrimEnd('\') + '\'
        $inside = $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or
                  $full.TrimEnd('\').Equals($root.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
        if (-not $inside) { return $false }
        if ($MustExist -and -not (Test-Path -LiteralPath $full)) { return $false }
        return $true
    } catch {
        return $false
    }
}

function Get-DefaultAppCatalog {
    # Curated subset relevant to PC-repair/MSP work, sourced from ChrisTitusTech/winutil's
    # config/applications.json (verified winget IDs, not guessed). This is intentionally a
    # curated subset, not a mirror of the full ~1800-line upstream file - a repair tech
    # reinstalling common software doesn't need winutil's full game-launcher/dev-tool catalog.
    return [ordered]@{
        # Browsers
        chrome     = @{ category='Browsers'; content='Google Chrome'; winget='Google.Chrome'; foss=$false }
        firefox    = @{ category='Browsers'; content='Mozilla Firefox'; winget='Mozilla.Firefox'; foss=$true }
        brave      = @{ category='Browsers'; content='Brave'; winget='Brave.Brave'; foss=$true }
        # Utilities
        '7zip'          = @{ category='Utilities'; content='7-Zip'; winget='7zip.7zip'; foss=$true }
        nanazip         = @{ category='Utilities'; content='NanaZip'; winget='M2Team.NanaZip'; foss=$true }
        bitwarden       = @{ category='Utilities'; content='Bitwarden'; winget='Bitwarden.Bitwarden'; foss=$true }
        keepassxc       = @{ category='Utilities'; content='KeePassXC'; winget='KeePassXCTeam.KeePassXC'; foss=$true }
        bulkcrapuninstaller = @{ category='Utilities'; content='Bulk Crap Uninstaller'; winget='Klocman.BulkCrapUninstaller'; foss=$true }
        googledrive     = @{ category='Utilities'; content='Google Drive'; winget='Google.GoogleDrive'; foss=$false }
        dropbox         = @{ category='Utilities'; content='Dropbox'; winget='Dropbox.Dropbox'; foss=$false }
        minitoolpartitionwizard = @{ category='Utilities'; content='MiniTool Partition Wizard'; winget='MiniTool.PartitionWizard.Free'; foss=$false }
        # Pro Tools / diagnostics (directly repair-relevant)
        cpuz            = @{ category='Pro Tools'; content='CPU-Z'; winget='CPUID.CPU-Z'; foss=$false }
        gpuz            = @{ category='Pro Tools'; content='GPU-Z'; winget='TechPowerUp.GPU-Z'; foss=$false }
        hwinfo          = @{ category='Pro Tools'; content='HWiNFO'; winget='REALiX.HWiNFO'; foss=$false }
        hwmonitor       = @{ category='Pro Tools'; content='HWMonitor'; winget='CPUID.HWMonitor'; foss=$false }
        crystaldiskinfo = @{ category='Pro Tools'; content='CrystalDiskInfo'; winget='CrystalDewWorld.CrystalDiskInfo'; foss=$true }
        crystaldiskmark = @{ category='Pro Tools'; content='CrystalDiskMark'; winget='CrystalDewWorld.CrystalDiskMark'; foss=$true }
        ddu             = @{ category='Pro Tools'; content='Display Driver Uninstaller'; winget='Wagnardsoft.DisplayDriverUninstaller'; foss=$true }
        advancedip      = @{ category='Pro Tools'; content='Advanced IP Scanner'; winget='Famatech.AdvancedIPScanner'; foss=$false }
        nmap            = @{ category='Pro Tools'; content='Nmap'; winget='Insecure.Nmap'; foss=$true }
        # Multimedia / document tools
        adobe           = @{ category='Multimedia Tools'; content='Adobe Acrobat Reader'; winget='Adobe.Acrobat.Reader.64-bit'; foss=$false }
        libreoffice     = @{ category='Multimedia Tools'; content='LibreOffice'; winget='TheDocumentFoundation.LibreOffice'; foss=$true }
        klite           = @{ category='Multimedia Tools'; content='K-Lite Codec Standard'; winget='CodecGuide.K-LiteCodecPack.Standard'; foss=$false }
        irfanview       = @{ category='Multimedia Tools'; content='IrfanView'; winget='IrfanSkiljan.IrfanView'; foss=$false }
        notepadplus     = @{ category='Multimedia Tools'; content='Notepad++'; winget='Notepad++.Notepad++'; foss=$true }
        # Microsoft Tools
        autoruns        = @{ category='Microsoft Tools'; content='Autoruns'; winget='Microsoft.Sysinternals.Autoruns'; foss=$false }
        onedrive        = @{ category='Microsoft Tools'; content='OneDrive'; winget='Microsoft.OneDrive'; foss=$false }
        dotnet8         = @{ category='Microsoft Tools'; content='.NET Desktop Runtime 8'; winget='Microsoft.DotNet.DesktopRuntime.8'; foss=$true }
        dotnet9         = @{ category='Microsoft Tools'; content='.NET Desktop Runtime 9'; winget='Microsoft.DotNet.DesktopRuntime.9'; foss=$true }
        # Communications
        discord         = @{ category='Communications'; content='Discord'; winget='Discord.Discord'; foss=$false }
    }
}

function Initialize-AppCatalog {
    $path = Join-Path $script:Paths.Config 'AppCatalog.json'
    if (Test-Path -LiteralPath $path) {
        try {
            $script:AppCatalog = ConvertTo-HashtableDeep (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
            return
        } catch {
            Write-Log "Config\AppCatalog.json is malformed - regenerating from defaults: $($_.Exception.Message)" 'Warning'
        }
    }
    $script:AppCatalog = Get-DefaultAppCatalog
    try {
        Write-AtomicText -Path $path -Content (ConvertTo-JsonSafe $script:AppCatalog)
        Add-Artifact -Path $path -Type 'Configuration' -Description 'Application catalog (editable - add/remove entries freely)'
    } catch {
        Write-Log "Could not write default AppCatalog.json: $($_.Exception.Message)" 'Warning'
    }
}

function Get-DefaultConfig {
    return @{
        SchemaVersion = 1
        CompanyName = 'Woodville PC & Tech'
        CompanyTagline = 'Professional PC Diagnostics, Repair & Maintenance'
        LogoPath = ''
        SDIOPath = $script:Paths.SDIO
        WSUSOfflinePath = $script:Paths.WSUS
        ToolPaths = @{
            KVRT = ''
            Sophos = ''
            Everything = ''
            Winget = ''
            Chocolatey = ''
            Scoop = ''
        }
        EnabledStages = @(
            'Preflight','Audit','Backup','Hardware','Storage','Security','EventLogs',
            'Performance','Repair','Cleanup','Network','Drivers','WindowsUpdate',
            'Debloat','Applications','WindowsConfig','Restore','Verification',
            'Finalize','FinalReport'
        )
        Retention = @{
            Days = 30
            KeepReports = 30
            KeepLogs = 30
        }
        ReportSettings = @{
            WriteHtml = $true
            WriteJson = $true
            WriteCsv = $true
            CustomerSafe = $true
        }
        SecuritySettings = @{
            DefenderEnabled = $true
            OptionalToolsRequireManifest = $true
            HashOptionalTools = $true
        }
        Safety = @{
            AllowReboot = $false
            AllowDriverInstall = $false
            AllowDebloatChanges = $false
            AllowNetworkReset = $false
            AllowWindowsUpdateRepair = $false
        }
        Debloat = @{
            NeverRemove = @(
                'Microsoft.WindowsStore','Microsoft.SecHealthUI','Microsoft.Windows.Photos',
                'Microsoft.WindowsCalculator','Microsoft.DesktopAppInstaller','Microsoft.VCLibs*',
                'Microsoft.NET.Native*','Microsoft.UI.Xaml*','Microsoft.WindowsNotepad',
                'Microsoft.Paint','Microsoft.ScreenSketch'
            )
            RemoveCandidates = @(
                'Microsoft.BingNews','Microsoft.BingWeather','Microsoft.GetHelp','Microsoft.Getstarted',
                'Microsoft.Microsoft3DViewer','Microsoft.MicrosoftOfficeHub','Microsoft.MicrosoftSolitaireCollection',
                'Microsoft.MixedReality.Portal','Microsoft.People','Microsoft.WindowsFeedbackHub',
                'Microsoft.YourPhone','Microsoft.ZuneMusic','Microsoft.ZuneVideo','Microsoft.XboxApp',
                'Microsoft.Xbox.TCUI','Microsoft.XboxGameOverlay','Microsoft.XboxGamingOverlay',
                'Microsoft.XboxIdentityProvider','Microsoft.XboxSpeechToTextOverlay',
                'king.com.CandyCrushSaga','SpotifyAB.SpotifyMusic'
            )
        }
    }
}

function Get-CompanyBranding {
    $name = if ($script:Config.CompanyName) { $script:Config.CompanyName } else { 'Woodville PC & Tech' }
    $tagline = if ($script:Config.CompanyTagline) { $script:Config.CompanyTagline } else { 'Professional PC Diagnostics, Repair & Maintenance' }
    $logoDataUri = $null
    try {
        if ($script:Config.LogoPath -and (Test-Path -LiteralPath $script:Config.LogoPath)) {
            $ext = ([IO.Path]::GetExtension($script:Config.LogoPath)).TrimStart('.').ToLower()
            $mime = if ($ext -eq 'jpg') { 'jpeg' } else { $ext }
            $bytes = [IO.File]::ReadAllBytes($script:Config.LogoPath)
            $logoDataUri = 'data:image/{0};base64,{1}' -f $mime, [Convert]::ToBase64String($bytes)
        } else {
            $clean = ($script:DefaultLogoBase64 -replace '\s', '')
            [Convert]::FromBase64String($clean) | Out-Null
            $logoDataUri = 'data:image/png;base64,' + $clean
        }
    } catch {
        Write-Log "Could not load company logo - report will render without one: $($_.Exception.Message)" 'Warning'
    }
    return [pscustomobject]@{ Name = $name; Tagline = $tagline; LogoDataUri = $logoDataUri }
}

function ConvertTo-HashtableDeep {
    param([object]$InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $h = @{}
        foreach ($key in $InputObject.Keys) {
            $h[$key] = ConvertTo-HashtableDeep $InputObject[$key]
        }
        return $h
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and
        -not ($InputObject -is [string])) {
        $a = @()
        foreach ($item in $InputObject) {
            $a += ,(ConvertTo-HashtableDeep $item)
        }
        return $a
    }
    return $InputObject
}

function Merge-Config {
    param([hashtable]$Base,[hashtable]$Override)
    foreach ($key in $Override.Keys) {
        if ($Base.ContainsKey($key) -and $Base[$key] -is [hashtable] -and $Override[$key] -is [hashtable]) {
            Merge-Config -Base $Base[$key] -Override $Override[$key]
        } else {
            $Base[$key] = $Override[$key]
        }
    }
    return $Base
}

function Initialize-Config {
    $defaultPath = Join-Path $script:Paths.Config 'Toolkit.json'
    $path = if ($ConfigPath) { $ConfigPath } else { $defaultPath }

    $script:Config = Get-DefaultConfig
    if (Test-Path -LiteralPath $path) {
        try {
            $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json
            $script:Config = Merge-Config -Base $script:Config -Override (ConvertTo-HashtableDeep $raw)
        } catch {
            Write-Log "Malformed configuration: $($_.Exception.Message)" 'Warning'
            Add-Finding -Category 'Configuration' -Severity 'Medium' `
                -Description 'Toolkit configuration could not be parsed; safe defaults were used.' `
                -Evidence $path -RecommendedAction 'Repair or replace Config\Toolkit.json.' -Confidence 'High'
        }
    } else {
        try {
            Write-AtomicText -Path $defaultPath -Content (ConvertTo-JsonSafe $script:Config)
            Add-Artifact -Path $defaultPath -Type 'Configuration' -Description 'Default toolkit configuration'
        } catch {
            Write-Log "Could not create default configuration: $($_.Exception.Message)" 'Warning'
        }
    }

    if (-not $script:Config.ToolPaths) { $script:Config.ToolPaths = @{} }
}

function Initialize-Logging {
    $logName = 'Run_{0}_{1}.log' -f $script:RunId, (Get-Date -Format 'yyyyMMdd_HHmmss')
    $path = Join-Path $script:Paths.Logs $logName
    try {
        $script:TranscriptWriter = New-Object IO.StreamWriter($path, $true, (New-Object Text.UTF8Encoding($false)))
        $script:TranscriptWriter.AutoFlush = $true
        Add-Artifact -Path $path -Type 'Log' -Description 'Run log'
    } catch {
        $script:TranscriptWriter = $null
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('Debug','Info','Success','Warning','Error')][string]$Level = 'Info'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level.ToUpper(), $Message
    switch ($Level) {
        'Error' { Write-Host $line -ForegroundColor Red }
        'Warning' { Write-Host $line -ForegroundColor Yellow }
        'Success' { Write-Host $line -ForegroundColor Green }
        'Debug' { if ($LogLevel -eq 'Debug') { Write-Host $line -ForegroundColor DarkGray } }
        default { Write-Host $line }
    }
    if ($script:TranscriptWriter) {
        try { $script:TranscriptWriter.WriteLine($line) } catch {}
    }
}

function Add-Artifact {
    param(
        [string]$Path,
        [string]$Type = 'File',
        [string]$Description = '',
        [string]$Hash = ''
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $item = [ordered]@{
        RunId = $script:RunId
        Path = $Path
        Type = $Type
        Description = $Description
        Exists = (Test-Path -LiteralPath $Path)
        Hash = $Hash
    }
    [void]$script:Artifacts.Add([pscustomobject]$item)
}

function Add-Finding {
    param(
        [Parameter(Mandatory=$true)][string]$Category,
        [ValidateSet('Informational','Low','Medium','High','Critical')]
        [string]$Severity = 'Informational',
        [Parameter(Mandatory=$true)][string]$Description,
        [string]$Evidence = '',
        [string]$LikelyCause = '',
        [string]$RecommendedAction = '',
        [ValidateSet('Low','Medium','High')][string]$Confidence = 'Medium'
    )
    [void]$script:Findings.Add([pscustomobject][ordered]@{
        RunId = $script:RunId
        Category = $Category
        Severity = $Severity
        Description = $Description
        Evidence = $Evidence
        LikelyCause = $LikelyCause
        RecommendedAction = $RecommendedAction
        Confidence = $Confidence
    })
}

function Add-Change {
    param(
        [string]$Action,
        [string]$Target,
        [string]$Result,
        [bool]$Changed = $false,
        [string]$RiskLevel = 'SAFE'
    )
    [void]$script:Changes.Add([pscustomobject][ordered]@{
        RunId = $script:RunId
        Action = $Action
        Target = $Target
        Result = $Result
        Changed = $Changed
        RiskLevel = $RiskLevel
        WhatIf = [bool]$WhatIf
        TimeUtc = Get-UtcString
    })
}

function New-Result {
    param(
        [string]$StageName,
        [string]$Task,
        [ValidateSet('NotRun','Running','Succeeded','SucceededWithWarnings','Failed','Skipped','Blocked','RequiresReboot','NotApplicable')]
        [string]$Status = 'Succeeded',
        [ValidateSet('Informational','Low','Medium','High','Critical')]
        [string]$Severity = 'Informational',
        [bool]$Changed = $false,
        [bool]$Skipped = $false,
        $ExitCode = $null,
        [string]$Message = '',
        [object]$Details = $null,
        [string[]]$Warnings = @(),
        [string[]]$Errors = @(),
        [string[]]$ArtifactPaths = @(),
        [bool]$Reboot = $false,
        [bool]$RequiresTechnician = $false,
        [string]$RiskLevel = 'SAFE',
        [string]$Tool = '',
        [string]$ToolVersion = ''
    )
    return [pscustomobject][ordered]@{
        RunId = $script:RunId
        Stage = $StageName
        Task = $Task
        StartedUtc = Get-UtcString
        CompletedUtc = Get-UtcString
        DurationSeconds = 0
        Status = $Status
        Severity = $Severity
        Changed = $Changed
        Skipped = $Skipped
        WhatIf = [bool]$WhatIf
        ExitCode = $ExitCode
        Message = $Message
        Details = $Details
        Warnings = $Warnings
        Errors = $Errors
        Artifacts = $ArtifactPaths
        RebootRequired = $Reboot
        RequiresTechnician = $RequiresTechnician
        RiskLevel = $RiskLevel
        Tool = $Tool
        ToolVersion = $ToolVersion
    }
}

function Add-Result {
    param([object]$Result)
    [void]$script:Results.Add($Result)
    return $Result
}

function Get-Executable {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    try { return (Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1) } catch { return $null }
}

function Get-ToolStatus {
    param([string]$Name,[string]$ConfiguredPath='')
    $candidate = $ConfiguredPath
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
        return [pscustomobject]@{ Name=$Name; Status='Installed'; Path=$candidate }
    }
    $cmd = Get-Executable $Name
    if ($cmd) {
        return [pscustomobject]@{ Name=$Name; Status='Installed'; Path=$cmd.Source }
    }
    return [pscustomobject]@{ Name=$Name; Status='NotInstalled'; Path='' }
}

function ConvertTo-QuotedArgumentString {
    # Windows PowerShell 5.1/.NET Framework does not expose ProcessStartInfo.ArgumentList,
    # so every process launcher in this script builds a single quoted argument string
    # through this one function instead of duplicating the quoting logic.
    param([string[]]$ArgumentList = @())
    $quoted = @()
    foreach ($arg in $ArgumentList) {
        $a = [string]$arg
        if ($a -match '[\s"]') {
            $a = $a -replace '(\\*)"', '$1$1\"'
            $a = $a -replace '(\\+)$', '$1$1'
            $quoted += '"' + $a + '"'
        } else {
            $quoted += $a
        }
    }
    return ($quoted -join ' ')
}

function Invoke-ExternalProcess {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = '',
        [int]$TimeoutSeconds = 300,
        [switch]$AllowMissing
    )
    $start = Get-Date
    if (-not (Test-Path -LiteralPath $FilePath) -and -not (Get-Executable ([IO.Path]::GetFileName($FilePath)))) {
        if ($AllowMissing) {
            return New-Result -StageName 'Tool' -Task $FilePath -Status 'NotInstalled' `
                -Skipped $true -Message 'Optional tool is not installed.'
        }
        return New-Result -StageName 'Tool' -Task $FilePath -Status 'NotAvailable' `
            -Skipped $true -Message 'Executable was not found.'
    }

    if ($WhatIf) {
        return New-Result -StageName 'Tool' -Task $FilePath -Status 'Skipped' -Skipped $true `
            -Message ('WhatIf: would execute {0} {1}' -f $FilePath,($ArgumentList -join ' '))
    }

    $stdout = Join-Path $script:Paths.Cache ('stdout_{0}.txt' -f [guid]::NewGuid())
    $stderr = Join-Path $script:Paths.Cache ('stderr_{0}.txt' -f [guid]::NewGuid())
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    $psi.Arguments = ConvertTo-QuotedArgumentString -ArgumentList $ArgumentList

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $psi
    try {
        if (-not $process.Start()) {
            return New-Result -StageName 'Tool' -Task $FilePath -Status 'Failed' -Message 'Process failed to start.'
        }
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        $exited = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $exited) {
            try { $process.Kill() } catch {}
            return New-Result -StageName 'Tool' -Task $FilePath -Status 'Failed' `
                -Message "Process timed out after $TimeoutSeconds seconds." -Errors @('Timeout')
        }
        $process.WaitForExit()
        $exit = $process.ExitCode
        $out = $outTask.Result
        $err = $errTask.Result
        Write-AtomicText -Path $stdout -Content $out
        Write-AtomicText -Path $stderr -Content $err
        Add-Artifact -Path $stdout -Type 'ProcessStdout' -Description $FilePath
        Add-Artifact -Path $stderr -Type 'ProcessStderr' -Description $FilePath

        $status = if ($exit -eq 0) { 'Succeeded' } else { 'Failed' }
        $msg = if ($exit -eq 0) { 'Process completed with exit code 0.' } else { "Process exited with code $exit." }
        return New-Result -StageName 'Tool' -Task $FilePath -Status $status `
            -ExitCode $exit -Message $msg -Details ([pscustomobject]@{Stdout=$out;Stderr=$err}) `
            -ArtifactPaths @($stdout,$stderr)
    } catch {
        return New-Result -StageName 'Tool' -Task $FilePath -Status 'Failed' `
            -Message 'Exception while executing process.' -Errors @($_.Exception.Message)
    } finally {
        $process.Dispose()
    }
}

function Write-State {
    $statePath = Join-Path $script:Paths.State 'RunState.json'
    try {
        Write-AtomicText -Path $statePath -Content (ConvertTo-JsonSafe $script:State)
        Add-Artifact -Path $statePath -Type 'State' -Description 'Persistent run state'
    } catch {
        Write-Log "Unable to persist run state: $($_.Exception.Message)" 'Warning'
    }
}

function Read-State {
    $statePath = Join-Path $script:Paths.State 'RunState.json'
    if (-not (Test-Path -LiteralPath $statePath)) { return $null }
    try {
        return (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json)
    } catch {
        Add-Finding -Category 'State' -Severity 'Low' `
            -Description 'Existing toolkit state file is unreadable.' `
            -Evidence $statePath -RecommendedAction 'Review or remove the stale state file after preserving it for investigation.' `
            -Confidence 'High'
        return $null
    }
}

function Initialize-State {
    $old = Read-State
    if ($old -and $old.Status -eq 'Running') {
        $script:PreviousStateDetected = $true
        Add-Finding -Category 'Run State' -Severity 'Medium' `
            -Description 'A previous toolkit run appears to have ended without finalization.' `
            -Evidence ('Previous RunId: ' + $old.RunId) `
            -RecommendedAction 'Use RebootResume/Verification to review and resume; destructive stages are not automatically replayed.' `
            -Confidence 'High'
    }

    $script:State = [ordered]@{
        SchemaVersion = 1
        RunId = $script:RunId
        Status = 'Running'
        StartUtc = $script:StartUtc.ToString('o')
        EndUtc = ''
        CurrentStage = ''
        CompletedStages = @()
        FailedStages = @()
        PendingStages = @()
        RebootRequired = $false
        PreviousRunDetected = $script:PreviousStateDetected
        ClientName = $ClientName
        TicketNumber = $TicketNumber
        Technician = $TechName
        ReportedIssue = $ReportedIssue
        WhatIf = [bool]$WhatIf
    }
    Write-State
}

function Test-InternetConnectivity {
    if ($OfflineMode) {
        Add-Result (New-Result 'Preflight' 'Internet connectivity' 'Skipped' -Skipped:$true -Message 'OfflineMode was requested.')
        return $false
    }
    $targets = @('https://www.microsoft.com','https://www.cloudflare.com')
    foreach ($u in $targets) {
        try {
            $r = Invoke-WebRequest -Uri $u -UseBasicParsing -Method Head -TimeoutSec 8 -ErrorAction Stop
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) {
                Add-Result (New-Result 'Preflight' 'Internet connectivity' 'Succeeded' -Message ('Reachable: ' + $u))
                return $true
            }
        } catch {}
    }
    Add-Result (New-Result 'Preflight' 'Internet connectivity' 'SucceededWithWarnings' `
        -Severity 'Low' -Message 'No tested HTTPS endpoint responded. Offline operation remains available.')
    Add-Finding -Category 'Network' -Severity 'Low' `
        -Description 'Internet connectivity could not be confirmed.' `
        -RecommendedAction 'Check adapter, gateway, DNS, proxy/VPN and firewall configuration.' -Confidence 'Medium'
    return $false
}

function Get-SystemInventory {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $gpu = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Select-Object Name,DriverVersion,VideoMemoryType,AdapterRAM,Status)
    $ramGB = if ($cs) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 2) } else { $null }
    return [pscustomobject][ordered]@{
        ComputerName = $env:COMPUTERNAME
        Manufacturer = $cs.Manufacturer
        Model = $cs.Model
        OS = $os.Caption
        OSVersion = $os.Version
        Build = $os.BuildNumber
        InstallDate = $os.InstallDate
        LastBoot = $os.LastBootUpTime
        UptimeHours = if ($os) { [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours,2) } else {$null}
        CPU = $cpu.Name
        CPUCores = $cpu.NumberOfCores
        CPUThreads = $cpu.NumberOfLogicalProcessors
        RAMGB = $ramGB
        BIOS = $bios.SMBIOSBIOSVersion
        BIOSDate = $bios.ReleaseDate
        GPU = $gpu
        Architecture = $env:PROCESSOR_ARCHITECTURE
        PowerShell = $PSVersionTable.PSVersion.ToString()
        Is64BitOS = [Environment]::Is64BitOperatingSystem
    }
}

function Invoke-Audit {
    $info = Get-SystemInventory
    $script:State.System = $info
    Add-Result (New-Result 'Audit' 'System inventory' 'Succeeded' -Details $info -Message 'Core system inventory collected.')

    if ($info.UptimeHours -gt 168) {
        Add-Finding -Category 'Performance' -Severity 'Low' `
            -Description ('System uptime is approximately {0} hours.' -f $info.UptimeHours) `
            -Evidence $info.LastBoot -RecommendedAction 'Consider a normal restart if operationally appropriate.' -Confidence 'High'
    }

    $drives = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue |
        Select-Object DeviceID,FileSystem,VolumeName,Size,FreeSpace)
    $script:State.Drives = $drives
    foreach ($d in $drives) {
        if ($d.Size -gt 0) {
            $free = [math]::Round(($d.FreeSpace / $d.Size) * 100,1)
            if ($free -lt 10) {
                Add-Finding -Category 'Storage' -Severity 'High' `
                    -Description ("Drive {0} has only {1}% free space." -f $d.DeviceID,$free) `
                    -Evidence ("Free bytes: {0:N0}; total: {1:N0}" -f $d.FreeSpace,$d.Size) `
                    -RecommendedAction 'Free space before repair/update operations; low space can cause Windows failures.' -Confidence 'High'
            } elseif ($free -lt 20) {
                Add-Finding -Category 'Storage' -Severity 'Medium' `
                    -Description ("Drive {0} has {1}% free space." -f $d.DeviceID,$free) `
                    -RecommendedAction 'Plan cleanup or storage expansion.' -Confidence 'High'
            }
        }
    }

    $startup = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue |
        Select-Object Name,Command,Location,User)
    $script:State.StartupCount = $startup.Count

    $page = @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue |
        Select-Object Name,AllocatedBaseSize,CurrentUsage,PeakUsage)
    $script:State.PageFile = $page

    Add-Result (New-Result 'Audit' 'Startup and paging inventory' 'Succeeded' `
        -Details ([pscustomobject]@{Startup=$startup;PageFile=$page}) `
        -Message 'Startup entries and pagefile usage collected.')
}

function Invoke-Hardware {
    $items = [ordered]@{}
    $items.Memory = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue |
        Select-Object Manufacturer,PartNumber,Capacity,Speed,ConfiguredClockSpeed,SerialNumber)
    $items.Battery = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue |
        Select-Object Name,Status,EstimatedChargeRemaining,EstimatedRunTime)
    $items.TPM = @(Get-CimInstance -Namespace root\CIMV2\Security\MicrosoftTpm `
        -ClassName Win32_Tpm -ErrorAction SilentlyContinue |
        Select-Object IsEnabled_InitialValue,IsActivated_InitialValue,SpecVersion)
    $items.PnPErrors = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object { $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 0 } |
        Select-Object Name,PNPClass,ConfigManagerErrorCode,Status)

    foreach ($d in $items.PnPErrors) {
        Add-Finding -Category 'Hardware' -Severity 'High' `
            -Description ('Device Manager reports a problem with: ' + $d.Name) `
            -Evidence ('ConfigManagerErrorCode=' + $d.ConfigManagerErrorCode) `
            -RecommendedAction 'Inspect Device Manager and obtain the correct vendor driver before making changes.' `
            -Confidence 'High'
    }

    $secureBoot = $null
    try { $secureBoot = Confirm-SecureBootUEFI -ErrorAction Stop } catch {}
    $bitlocker = @()
    $manage = Get-Command manage-bde.exe -ErrorAction SilentlyContinue
    if ($manage) {
        try { $bitlocker = & $manage.Source -status 2>&1 | Out-String } catch {}
    }
    $items.SecureBoot = $secureBoot
    $items.BitLocker = $bitlocker

    Add-Result (New-Result 'Hardware' 'Hardware health inventory' 'Succeeded' `
        -Details $items -Message 'Hardware inventory and problem-device checks completed.')
}

function Invoke-Storage {
    $disks = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue |
        Select-Object Index,Model,SerialNumber,InterfaceType,MediaType,Size,Status,PNPDeviceID)
    $volumes = @(Get-CimInstance Win32_Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -eq 3 } |
        Select-Object DriveLetter,Label,FileSystem,Capacity,FreeSpace,HealthStatus)

    foreach ($d in $disks) {
        if ($d.Status -and $d.Status -notin @('OK','Online')) {
            Add-Finding -Category 'Storage' -Severity 'High' `
                -Description ('Disk reports status: ' + $d.Model) `
                -Evidence $d.Status -RecommendedAction 'Back up data and investigate storage health before repair.' -Confidence 'High'
        }
    }

    $smart = @(Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus `
        -ErrorAction SilentlyContinue)
    foreach ($s in $smart) {
        if ($s.PredictFailure) {
            Add-Finding -Category 'Storage' -Severity 'Critical' `
                -Description 'A storage device reports a SMART failure prediction.' `
                -Evidence ('PredictFailure=' + $s.PredictFailure) `
                -RecommendedAction 'Back up immediately and replace the affected drive.' -Confidence 'High'
        }
    }

    Add-Result (New-Result 'Storage' 'Disk, volume and SMART inventory' 'Succeeded' `
        -Details ([pscustomobject]@{Disks=$disks;Volumes=$volumes;SMART=$smart}) `
        -Message 'Storage inventory completed. No destructive disk operation was performed.')
}

function Invoke-Security {
    $defender = Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue
    $status = $null
    if ($defender) {
        try { $status = Get-MpComputerStatus -ErrorAction Stop } catch {}
    }
    if ($status) {
        if (-not $status.RealTimeProtectionEnabled) {
            Add-Finding -Category 'Security' -Severity 'High' `
                -Description 'Microsoft Defender real-time protection is not enabled.' `
                -Evidence ('RealTimeProtectionEnabled=' + $status.RealTimeProtectionEnabled) `
                -RecommendedAction 'Verify the installed security product and enable protection if appropriate.' -Confidence 'High'
        }
        Add-Result (New-Result 'Security' 'Microsoft Defender status' 'Succeeded' `
            -Details ($status | Select-Object AMServiceEnabled,AntivirusEnabled,AntispywareEnabled,
                RealTimeProtectionEnabled,BehaviorMonitorEnabled,IoavProtectionEnabled,NISEnabled) `
            -Message 'Defender status collected.')
    } else {
        Add-Result (New-Result 'Security' 'Microsoft Defender status' 'NotApplicable' `
            -Message 'Defender cmdlets are unavailable on this system.')
    }

    $optional = @(
        (Get-ToolStatus 'KVRT' $script:Config.ToolPaths.KVRT),
        (Get-ToolStatus 'Sophos' $script:Config.ToolPaths.Sophos)
    )
    foreach ($tool in $optional) {
        Add-Result (New-Result 'Security' ($tool.Name + ' availability') `
            $(if ($tool.Status -eq 'Installed') {'Succeeded'} else {'NotInstalled'}) `
            -Skipped:($tool.Status -ne 'Installed') `
            -Message ($tool.Status + ': ' + $tool.Path))
    }

    if (-not $SkipMalware) {
        $scan = Get-Command Start-MpScan -ErrorAction SilentlyContinue
        if ($scan) {
            if ($WhatIf) {
                Add-Result (New-Result 'Security' 'Defender quick scan' 'Skipped' -Skipped:$true `
                    -Message 'WhatIf: Defender scan was not started.')
            } else {
                try {
                    Start-MpScan -ScanType QuickScan -ErrorAction Stop
                    Add-Result (New-Result 'Security' 'Defender quick scan' 'Succeeded' `
                        -Message 'Defender accepted the quick-scan request. This does not by itself prove the system is clean.')
                } catch {
                    Add-Result (New-Result 'Security' 'Defender quick scan' 'Failed' `
                        -Message 'Defender scan request failed.' -Errors @($_.Exception.Message))
                }
            }
        } else {
            Add-Result (New-Result 'Security' 'Defender quick scan' 'NotApplicable' -Skipped:$true `
                -Message 'Start-MpScan is unavailable.')
        }
    }
}

function Invoke-EventLogs {
    $logs = @('System','Application','Security')
    foreach ($name in $logs) {
        try {
            $events = @(Get-WinEvent -FilterHashtable @{LogName=$name;StartTime=(Get-Date).AddDays(-7)} `
                -ErrorAction Stop)
            $errors = @($events | Where-Object {$_.LevelDisplayName -eq 'Error'})
            $crit = @($events | Where-Object {$_.LevelDisplayName -eq 'Critical'})
            Add-Result (New-Result 'EventLogs' ($name + ' event review') 'Succeeded' `
                -Details ([pscustomobject]@{
                    Total=$events.Count
                    Errors=$errors.Count
                    Critical=$crit.Count
                    Recent=$events | Select-Object -First 100 TimeCreated,Id,ProviderName,LevelDisplayName,Message
                }) -Message ('Reviewed {0} events from the last 7 days.' -f $events.Count))
            if ($crit.Count -gt 0) {
                Add-Finding -Category 'Event Logs' -Severity 'High' `
                    -Description ("$name contains $($crit.Count) critical event(s) in the last 7 days.") `
                    -Evidence (($crit | Select-Object -First 5 | ForEach-Object { "$($_.TimeCreated) ID=$($_.Id) $($_.ProviderName)" }) -join '; ') `
                    -RecommendedAction 'Review the corresponding event details and correlate with the reported symptom.' -Confidence 'High'
            }
        } catch {
            Add-Result (New-Result 'EventLogs' ($name + ' event review') 'NotAvailable' `
                -Skipped:$true -Message $_.Exception.Message)
        }
    }

    $whea = @(Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-WHEA-Logger';StartTime=(Get-Date).AddDays(-30)} `
        -ErrorAction SilentlyContinue)
    if ($whea.Count -gt 0) {
        Add-Finding -Category 'Hardware' -Severity 'High' `
            -Description ("WHEA-Logger has $($whea.Count) event(s) in the last 30 days.") `
            -Evidence (($whea | Select-Object -First 10 | ForEach-Object {$_.Id}) -join ', ') `
            -RecommendedAction 'Investigate CPU, RAM, motherboard, PCIe and storage hardware before repeated OS repair.' `
            -Confidence 'High'
    }
}

function Invoke-Performance {
    $cpu = try {
        @(Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 3 -ErrorAction Stop)
    } catch {
        # Performance counters are sometimes corrupted on exactly the machines this
        # toolkit is used on - Get-Counter can throw a terminating error even with
        # -ErrorAction SilentlyContinue in that case, so catch it explicitly.
        Add-Finding -Category 'Performance' -Severity 'Low' `
            -Description 'Performance counters could not be read.' `
            -Evidence $_.Exception.Message `
            -RecommendedAction 'Consider rebuilding performance counters (lodctr /R) if performance data is needed.' `
            -Confidence 'Medium'
        @()
    }
    $mem = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $top = @(Get-Process -ErrorAction SilentlyContinue |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 15 Name,Id,CPU,WorkingSet64)
    Add-Result (New-Result 'Performance' 'Performance snapshot' 'Succeeded' `
        -Details ([pscustomobject]@{
            CpuSamples=$cpu.CounterSamples | Select-Object Timestamp,CookedValue
            MemoryFreeGB=if($mem){[math]::Round($mem.FreePhysicalMemory/1MB,2)}else{$null}
            MemoryTotalGB=if($mem){[math]::Round($mem.TotalVisibleMemorySize/1MB,2)}else{$null}
            TopProcesses=$top
        }) -Message 'CPU, memory and top-process snapshot collected.')
}

function Invoke-Backup {
    if ($SkipBackup) {
        Add-Result (New-Result 'Backup' 'Pre-repair backup' 'Skipped' -Skipped:$true `
            -Message 'SkipBackup was requested.')
        return
    }

    $dir = Join-Path $script:Paths.Backups $script:RunId
    if (-not $WhatIf) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $manifest = [ordered]@{
        RunId = $script:RunId
        CreatedUtc = Get-UtcString
        System = Get-SystemInventory
        Files = @()
    }

    $driversDir = Join-Path $dir 'Drivers'
    if (-not $WhatIf -and -not (Test-Path -LiteralPath $driversDir)) {
        New-Item -ItemType Directory -Path $driversDir -Force | Out-Null
    }
    $targets = @(
        @{Name='Registry-HKLM-Software'; Command='reg.exe'; Args=@('export','HKLM\SOFTWARE',(Join-Path $dir 'HKLM_SOFTWARE.reg'),'/y')},
        @{Name='Registry-HKCU-Software'; Command='reg.exe'; Args=@('export','HKCU\SOFTWARE',(Join-Path $dir 'HKCU_SOFTWARE.reg'),'/y')},
        @{Name='DriverStore-Export'; Command='pnputil.exe'; Args=@('/export-driver','*',$driversDir)}
    )

    foreach ($t in $targets) {
        if ($WhatIf) {
            Add-Change -Action 'Backup' -Target $t.Name -Result 'Would execute' -RiskLevel 'LOW'
            continue
        }
        $cmd = Get-Executable $t.Command
        if (-not $cmd) {
            Add-Result (New-Result 'Backup' $t.Name 'NotAvailable' -Skipped:$true `
                -Message ($t.Command + ' is not available.'))
            continue
        }
        $r = Invoke-ExternalProcess -FilePath $cmd.Source -ArgumentList $t.Args -TimeoutSeconds 300
        $r.Stage = 'Backup'
        [void]$script:Results.Add($r)
        if ($r.Status -eq 'Succeeded') {
            Add-Change -Action 'Backup' -Target $t.Name -Result 'Created' -Changed:$true -RiskLevel 'LOW'
        }
    }

    try {
        $inventoryPath = Join-Path $dir 'SystemInventory.json'
        Write-AtomicText -Path $inventoryPath -Content (ConvertTo-JsonSafe (Get-SystemInventory))
        Add-Artifact -Path $inventoryPath -Type 'Backup' -Description 'System inventory backup'
        $manifest.Files += $inventoryPath
        Write-AtomicText -Path (Join-Path $dir 'Manifest.json') -Content (ConvertTo-JsonSafe $manifest)
        Add-Artifact -Path (Join-Path $dir 'Manifest.json') -Type 'BackupManifest' -Description 'Backup manifest'
        [void]$script:Backups.Add($dir)
        Add-Result (New-Result 'Backup' 'Backup manifest' 'Succeeded' -Message ('Backup set: ' + $dir))
    } catch {
        Add-Result (New-Result 'Backup' 'Backup manifest' 'Failed' -Errors @($_.Exception.Message))
    }
}

function Invoke-SystemRepair {
    if ($SkipRepair) {
        Add-Result (New-Result 'Repair' 'Repair operations' 'Skipped' -Skipped:$true -Message 'SkipRepair was requested.')
        return
    }

    if ($WhatIf) {
        foreach ($x in @('DISM CheckHealth','DISM ScanHealth','DISM RestoreHealth','SFC /scannow')) {
            Add-Result (New-Result 'Repair' $x 'Skipped' -Skipped:$true `
                -Message 'WhatIf: repair command not executed.')
        }
        return
    }

    $dism = Get-Executable 'DISM.exe'
    if ($dism) {
        foreach ($dismArgs in @(@('/Online','/Cleanup-Image','/CheckHealth'),
                            @('/Online','/Cleanup-Image','/ScanHealth'),
                            @('/Online','/Cleanup-Image','/RestoreHealth'))) {
            $r = Invoke-ExternalProcess -FilePath $dism.Source -ArgumentList $dismArgs -TimeoutSeconds 1800
            $r.Stage = 'Repair'
            [void]$script:Results.Add($r)
            if ($r.Status -eq 'Failed') {
                Add-Finding -Category 'Windows Repair' -Severity 'High' `
                    -Description ('DISM command failed: ' + ($dismArgs -join ' ')) `
                    -Evidence $r.Message -RecommendedAction 'Review DISM logs and component-store health before retrying.' `
                    -Confidence 'High'
            }
        }
    }

    $sfc = Get-Executable 'sfc.exe'
    if ($sfc) {
        $r = Invoke-ExternalProcess -FilePath $sfc.Source -ArgumentList @('/scannow') -TimeoutSeconds 1800
        $r.Stage = 'Repair'
        [void]$script:Results.Add($r)
        # SFC exit code 0 means it completed successfully, not necessarily that no corruption was found.
        if ($r.Status -eq 'Succeeded') {
            $text = [string]$r.Details.Stdout
            if ($text -match 'found corrupt files and successfully repaired them') {
                Add-Finding -Category 'Windows Repair' -Severity 'Medium' `
                    -Description 'SFC found and repaired corrupted system files.' `
                    -RecommendedAction 'Review CBS.log and run Verification after repair.' -Confidence 'High'
            } elseif ($text -match 'found corrupt files but was unable to fix some') {
                Add-Finding -Category 'Windows Repair' -Severity 'High' `
                    -Description 'SFC found corruption that it could not fully repair.' `
                    -RecommendedAction 'Review CBS.log and use DISM/component-store repair.' -Confidence 'High'
            }
        }
    }
}

function Invoke-Cleanup {
    if ($SkipCleanup) {
        Add-Result (New-Result 'Cleanup' 'Safe temporary-file cleanup' 'Skipped' -Skipped:$true `
            -Message 'SkipCleanup was requested.')
        return
    }

    $targets = @()
    if ($env:TEMP) { $targets += $env:TEMP }
    if ($env:LOCALAPPDATA) { $targets += (Join-Path $env:LOCALAPPDATA 'Temp') }
    $removed = 0
    $skipped = 0

    foreach ($root in ($targets | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $files = @(Get-ChildItem -LiteralPath $root -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
            Select-Object -First 1000)
        foreach ($file in $files) {
            if ($WhatIf) {
                $skipped++
                continue
            }
            try {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                $removed++
            } catch {}
        }
    }

    # Deliberately does NOT delete Prefetch, WinSxS, arbitrary System32 content,
    # browser databases, restore points, or registry keys.
    Add-Result (New-Result 'Cleanup' 'Safe temporary-file cleanup' 'Succeeded' `
        -Changed:($removed -gt 0) -Message ("Removed $removed old temp file(s); skipped $skipped in WhatIf mode."))
    Add-Change -Action 'Cleanup' -Target 'User/System temp locations' `
        -Result ("Removed $removed file(s)") -Changed:($removed -gt 0) -RiskLevel 'LOW'
}

function Invoke-Network {
    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue |
        Select-Object Name,InterfaceDescription,Status,LinkSpeed,MacAddress)
    $configs = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue |
        Select-Object InterfaceAlias,IPv4Address,IPv4DefaultGateway,DNSServer)
    $routes = @(Get-NetRoute -ErrorAction SilentlyContinue |
        Where-Object {$_.DestinationPrefix -eq '0.0.0.0/0'} |
        Select-Object InterfaceAlias,NextHop,RouteMetric)
    $proxy = $null
    try { $proxy = netsh winhttp show proxy 2>&1 | Out-String } catch {}

    Add-Result (New-Result 'Network' 'Network inventory' 'Succeeded' `
        -Details ([pscustomobject]@{Adapters=$adapters;IP=$configs;DefaultRoutes=$routes;WinHttpProxy=$proxy}) `
        -Message 'Network inventory collected. No reset was performed.')

    if ($configs.Count -eq 0) {
        Add-Finding -Category 'Network' -Severity 'High' `
            -Description 'No active IP configuration was found.' `
            -RecommendedAction 'Inspect adapters, drivers, DHCP/static configuration and physical connectivity.' -Confidence 'High'
    }
}

function Invoke-Drivers {
    $devices = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
        Select-Object DeviceName,DriverVersion,DriverDate,DriverProviderName,IsSigned,InfName)
    $bad = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object {$_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 0} |
        Select-Object Name,PNPClass,ConfigManagerErrorCode,Status)

    Add-Result (New-Result 'Drivers' 'Driver inventory' 'Succeeded' `
        -Details ([pscustomobject]@{SignedDrivers=$devices;ProblemDevices=$bad}) `
        -Message 'Driver inventory collected. No driver was installed or updated.')

    $sdioPath = $script:Config.SDIOPath
    $sdioExe = $null
    if ($sdioPath -and (Test-Path -LiteralPath $sdioPath)) {
        $sdioExe = @(Get-ChildItem -LiteralPath $sdioPath -Filter '*.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object {$_.Name -match 'SDI|Snappy'} | Select-Object -First 1)
    }
    if (-not $sdioExe) {
        Add-Result (New-Result 'Drivers' 'SDIO detection' 'NotInstalled' -Skipped:$true `
            -Message 'SDIO was not detected. No guessed path or download was used.')
        return
    }

    Add-Result (New-Result 'Drivers' 'SDIO detection' 'Succeeded' `
        -Message ('Detected SDIO executable: ' + $sdioExe.FullName))

    if (-not $script:Config.Safety.AllowDriverInstall) {
        Add-Result (New-Result 'Drivers' 'SDIO driver pack update' 'Skipped' -Skipped:$true `
            -Message 'Skipped: Safety.AllowDriverInstall is false in Config\Toolkit.json (default). SDIO was only detected, not run.')
        return
    }
    if ($WhatIf) {
        Add-Result (New-Result 'Drivers' 'SDIO driver pack update' 'Skipped' -Skipped:$true `
            -Message 'WhatIf: would run SDIO with -netupdate -autoclose (index update only, no install).')
        return
    }

    # -netupdate -autoclose are real, documented SDIO switches: download available driver
    # pack updates and close automatically. This does NOT install anything - installation
    # always goes through SDIO's own GUI so a technician reviews what's proposed first.
    $r = Invoke-ExternalProcess -FilePath $sdioExe.FullName -ArgumentList @('-netupdate','-autoclose') -TimeoutSeconds 900
    $r.Stage = 'Drivers'; $r.Task = 'SDIO driver pack index update'
    [void]$script:Results.Add($r)
    Add-Change -Action 'SDIO pack update' -Target $sdioExe.FullName `
        -Result $r.Status -Changed:($r.Status -eq 'Succeeded') -RiskLevel 'LOW'

    if (-not $Unattended) {
        try {
            Start-Process -FilePath $sdioExe.FullName | Out-Null
            Add-Result (New-Result 'Drivers' 'SDIO interactive launch' 'Succeeded' `
                -Message 'Launched SDIO for manual driver review/install. The toolkit does not select or install drivers itself.')
        } catch {
            Add-Result (New-Result 'Drivers' 'SDIO interactive launch' 'Failed' -Errors @($_.Exception.Message))
        }
    } else {
        Add-Result (New-Result 'Drivers' 'SDIO interactive launch' 'Skipped' -Skipped:$true `
            -Message 'Skipped interactive SDIO launch because Unattended was requested. Pack index was still updated above.')
    }
}

function Invoke-WindowsUpdate {
    $services = @(Get-Service -Name wuauserv,bits,cryptsvc,msiserver -ErrorAction SilentlyContinue |
        Select-Object Name,Status,StartType)
    $reboot = $false
    try {
        $pending = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        $pending2 = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        $reboot = $pending -or $pending2
    } catch {}
    if ($reboot) {
        $script:RebootRequired = $true
        $script:State.RebootRequired = $true
        Add-Finding -Category 'Windows Update' -Severity 'Medium' `
            -Description 'Windows reports a pending reboot.' `
            -RecommendedAction 'Plan a normal user-approved reboot before continuing update/repair work.' -Confidence 'High'
    }

    Add-Result (New-Result 'WindowsUpdate' 'Update service and reboot state' 'Succeeded' `
        -Details ([pscustomobject]@{Services=$services;PendingReboot=$reboot}) `
        -Message 'Windows Update services and pending-reboot state inspected.')

    $wsus = $script:Config.WSUSOfflinePath
    $wsusScript = $null
    if ($wsus -and (Test-Path -LiteralPath $wsus)) {
        foreach ($name in 'DoUpdate.cmd','Update.cmd') {
            $candidate = Join-Path $wsus (Join-Path 'client\cmd' $name)
            if (Test-Path -LiteralPath $candidate) { $wsusScript = $candidate; break }
        }
    }
    if (-not $wsusScript) {
        Add-Result (New-Result 'WindowsUpdate' 'WSUS Offline detection' 'NotInstalled' -Skipped:$true `
            -Message 'WSUS Offline was not detected under client\cmd. No guessed executable was invoked.')
        return
    }

    Add-Result (New-Result 'WindowsUpdate' 'WSUS Offline detection' 'Succeeded' `
        -Message ('Detected WSUS Offline client script: ' + $wsusScript))

    if (-not $script:Config.Safety.AllowWindowsUpdateRepair) {
        Add-Result (New-Result 'WindowsUpdate' 'WSUS Offline run' 'Skipped' -Skipped:$true `
            -Message 'Skipped: Safety.AllowWindowsUpdateRepair is false in Config\Toolkit.json (default). WSUS Offline was only detected, not run.')
        return
    }
    if ($WhatIf) {
        Add-Result (New-Result 'WindowsUpdate' 'WSUS Offline run' 'Skipped' -Skipped:$true `
            -Message ('WhatIf: would run ' + $wsusScript + ' /verify /updatecpp /instdotnet4 /instwmf /instmsse /showlog'))
        return
    }

    # WSUS Offline's own UpdateInstaller.exe cannot be run unattended (confirmed on the
    # vendor's own support forum) - it just launches this same client script with whatever
    # settings were picked in its GUI. Calling it directly bypasses that limitation.
    # A combined Windows 10 + 11 repo is auto-detected by the script itself against the
    # target machine's actual OS - no branching needed here.
    $r = Invoke-ExternalProcess -FilePath $wsusScript `
        -ArgumentList @('/verify','/updatecpp','/instdotnet4','/instwmf','/instmsse','/showlog') `
        -WorkingDirectory (Split-Path $wsusScript) -TimeoutSeconds 5400
    $r.Stage = 'WindowsUpdate'; $r.Task = 'WSUS Offline run'
    [void]$script:Results.Add($r)
    Add-Change -Action 'WSUS Offline' -Target $wsusScript -Result $r.Status `
        -Changed:($r.Status -eq 'Succeeded') -RiskLevel 'MEDIUM'
    if ($r.Status -ne 'Succeeded') {
        Add-Finding -Category 'Windows Update' -Severity 'Medium' `
            -Description 'WSUS Offline did not complete successfully.' -Evidence $r.Message `
            -RecommendedAction ('Check ' + $wsus + '\client\log for details.') -Confidence 'Medium'
    }
}

function Invoke-Debloat {
    if (-not $script:Config.Safety.AllowDebloatChanges) {
        Add-Result (New-Result 'Debloat' 'Debloat assessment' 'NotApplicable' `
            -Message 'Debloat is assessment-only (Safety.AllowDebloatChanges is false in Config\Toolkit.json, the default). No packages were removed.')
        Add-Finding -Category 'Debloat' -Severity 'Informational' `
            -Description 'Debloat changes are disabled by default to protect Windows Update, Defender, networking, audio, printing and Store functionality.' `
            -RecommendedAction 'Set Safety.AllowDebloatChanges to true in Config\Toolkit.json only after reviewing Config.Debloat.RemoveCandidates/NeverRemove.' `
            -Confidence 'High'
        return
    }
    if ($WhatIf) {
        Add-Result (New-Result 'Debloat' 'AppX removal' 'Skipped' -Skipped:$true `
            -Message 'WhatIf: would remove AppX packages matching Config.Debloat.RemoveCandidates, excluding NeverRemove.')
        return
    }

    $candidates = @($script:Config.Debloat.RemoveCandidates)
    $protected  = @($script:Config.Debloat.NeverRemove)
    $removed = New-Object System.Collections.Generic.List[string]
    $skipped = New-Object System.Collections.Generic.List[string]
    $failed  = New-Object System.Collections.Generic.List[string]

    foreach ($pattern in $candidates) {
        # Get-AppxPackage -AllUsers returns a duplicate object per user profile for the
        # same package, so dedupe by PackageFullName before acting on it.
        $pkgs = @(Get-AppxPackage -AllUsers -Name $pattern -ErrorAction SilentlyContinue |
            Sort-Object PackageFullName -Unique)
        foreach ($pkg in $pkgs) {
            $isProtected = $false
            foreach ($p in $protected) { if ($pkg.Name -like $p) { $isProtected = $true; break } }
            if ($isProtected) { $skipped.Add($pkg.Name); continue }
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                try { Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageFullName -ErrorAction Stop | Out-Null } catch {}
                $removed.Add($pkg.Name)
                Add-Change -Action 'Remove AppX' -Target $pkg.Name -Result 'Removed' -Changed:$true -RiskLevel 'LOW'
            } catch {
                $failed.Add($pkg.Name)
                Add-Change -Action 'Remove AppX' -Target $pkg.Name -Result $_.Exception.Message -Changed:$false -RiskLevel 'LOW'
            }
        }
    }

    Add-Result (New-Result 'Debloat' 'AppX removal' 'Succeeded' -Changed:($removed.Count -gt 0) `
        -Details ([pscustomobject]@{ Removed = @($removed); SkippedProtected = @($skipped); Failed = @($failed) }) `
        -Message ("Removed {0} package(s); {1} protected/skipped; {2} failed." -f $removed.Count, $skipped.Count, $failed.Count))
}

function Invoke-Applications {
    $winget = Get-ToolStatus 'winget' $script:Config.ToolPaths.Winget
    $choco = Get-ToolStatus 'choco' $script:Config.ToolPaths.Chocolatey
    $scoop = Get-ToolStatus 'scoop' $script:Config.ToolPaths.Scoop
    Add-Result (New-Result 'Applications' 'Application package-manager availability' 'Succeeded' `
        -Details ([pscustomobject]@{Winget=$winget;Chocolatey=$choco;Scoop=$scoop}) `
        -Message 'Package-manager availability checked. No applications were changed.')
    $apps = @(Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                  'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' `
        -ErrorAction SilentlyContinue |
        Where-Object {$_.DisplayName} |
        Select-Object DisplayName,DisplayVersion,Publisher,InstallDate |
        Sort-Object DisplayName -Unique)
    $script:State.ApplicationCount = $apps.Count
    Add-Result (New-Result 'Applications' 'Installed application inventory' 'Succeeded' `
        -Details $apps -Message ("Inventory contains $($apps.Count) application entries."))
}

function Show-ApplicationCatalog {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Host 'winget is not available on this system - cannot install from the catalog.' -ForegroundColor Yellow
        Add-Result (New-Result 'Applications' 'Application catalog install' 'NotApplicable' `
            -Message 'winget is unavailable.')
        Start-Sleep -Seconds 2
        return
    }

    $ids = @($script:AppCatalog.Keys | Sort-Object)
    $selectedIds = New-Object System.Collections.Generic.List[string]

    while ($true) {
        Clear-Host
        Write-Host 'APPLICATION CATALOG' -ForegroundColor Cyan
        Write-Host 'Toggle items by number, I to install selected, 0 to cancel.' -ForegroundColor DarkGray
        Write-Host ''
        $byCategory = $ids | Group-Object { $script:AppCatalog[$_].category }
        $index = 0
        $map = @{}
        foreach ($grp in ($byCategory | Sort-Object Name)) {
            Write-Host ("-- {0} --" -f $grp.Name) -ForegroundColor DarkCyan
            foreach ($id in ($grp.Group | Sort-Object)) {
                $index++
                $map[$index] = $id
                $mark = if ($selectedIds -contains $id) { '[x]' } else { '[ ]' }
                Write-Host (' {0,3}. {1} {2}' -f $index, $mark, $script:AppCatalog[$id].content)
            }
        }
        Write-Host ''
        Write-Host (' Selected: {0}' -f $selectedIds.Count)
        $choice = Read-Host 'Selection'
        if ($choice -eq '0') { return }
        if ($choice -match '^[Ii]$') { break }
        $n = 0
        if ([int]::TryParse($choice, [ref]$n) -and $map.ContainsKey($n)) {
            $id = $map[$n]
            if ($selectedIds -contains $id) { [void]$selectedIds.Remove($id) } else { $selectedIds.Add($id) }
        }
    }

    if ($selectedIds.Count -eq 0) { return }

    foreach ($id in $selectedIds) {
        $app = $script:AppCatalog[$id]
        if ($WhatIf) {
            Add-Result (New-Result 'Applications' ('Install ' + $app.content) 'Skipped' -Skipped:$true `
                -Message ('WhatIf: would run winget install --id ' + $app.winget))
            continue
        }
        Write-Log ('Installing ' + $app.content + ' via winget...')
        $r = Invoke-ExternalProcess -FilePath 'winget.exe' `
            -ArgumentList @('install','--id',$app.winget,'-e','--silent','--accept-package-agreements','--accept-source-agreements') `
            -TimeoutSeconds 600
        $r.Stage = 'Applications'; $r.Task = 'Install ' + $app.content; $r.Tool = $app.winget
        [void]$script:Results.Add($r)
        Add-Change -Action 'Install application' -Target $app.content -Result $r.Status `
            -Changed:($r.Status -eq 'Succeeded') -RiskLevel 'LOW'
    }
}

function Invoke-AppCatalogStage {
    if ($Unattended) {
        Add-Result (New-Result 'Applications' 'Application catalog install' 'Skipped' -Skipped:$true `
            -Message 'Skipped: application catalog is interactive and Unattended was requested.')
        return
    }
    Show-ApplicationCatalog
}

#region Windows Tweaks (Sophia-style reversible Get/Set/Restore architecture)
# This deliberately implements the PATTERN Sophia Script uses (read current state, save it,
# apply new state, offer restore) for a small, well-understood, easily-reversible set of
# tweaks - not a port of Sophia's much larger catalog. Each tweak is a plain registry value
# with a well-documented meaning, so Get/Set/Restore stay simple and auditable.

function Save-TweakSnapshot {
    param([Parameter(Mandatory=$true)][string]$TweakId, [Parameter(Mandatory=$true)]$PreviousValue)
    $dir = Join-Path (Join-Path $script:Paths.Backups $script:RunId) 'Tweaks'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $file = Join-Path $dir ('{0}_{1}.json' -f $TweakId, (Get-Date -Format 'yyyyMMddHHmmss'))
    $snapshot = [ordered]@{ TweakId = $TweakId; TimestampUtc = Get-UtcString; PreviousValue = $PreviousValue }
    Write-AtomicText -Path $file -Content (ConvertTo-JsonSafe $snapshot)
    Add-Artifact -Path $file -Type 'TweakBackup' -Description ('Rollback snapshot for ' + $TweakId)
    return $file
}

function Get-LatestTweakSnapshot {
    param([Parameter(Mandatory=$true)][string]$TweakId)
    if (-not (Test-Path -LiteralPath $script:Paths.Backups)) { return $null }
    $matches = Get-ChildItem -Path $script:Paths.Backups -Filter ($TweakId + '_*.json') -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending
    if (-not $matches -or $matches.Count -eq 0) { return $null }
    try { return (Get-Content -LiteralPath $matches[0].FullName -Raw | ConvertFrom-Json) } catch { return $null }
}

function Set-RegistryTweakValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Get-RegistryTweakValue {
    param([string]$Path, [string]$Name, $DefaultIfMissing)
    try {
        $v = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $v.$Name
    } catch {
        return $DefaultIfMissing
    }
}

# --- Tweak: File extensions visibility ------------------------------------------------
$script:ExplorerAdvancedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

function Get-FileExtensionsState {
    $v = Get-RegistryTweakValue -Path $script:ExplorerAdvancedKey -Name 'HideFileExt' -DefaultIfMissing 1
    return [pscustomobject]@{ TweakId='FileExtensions'; Current = if ($v -eq 0) {'Shown'} else {'Hidden'}; Recommended='Shown'; Risk='SAFE' }
}
function Set-FileExtensionsShown {
    param([bool]$Show)
    $old = Get-RegistryTweakValue -Path $script:ExplorerAdvancedKey -Name 'HideFileExt' -DefaultIfMissing 1
    Save-TweakSnapshot -TweakId 'FileExtensions' -PreviousValue $old | Out-Null
    Set-RegistryTweakValue -Path $script:ExplorerAdvancedKey -Name 'HideFileExt' -Value ([int](!$Show))
}
function Restore-FileExtensionsState {
    $snap = Get-LatestTweakSnapshot -TweakId 'FileExtensions'
    if (-not $snap) { return $false }
    Set-RegistryTweakValue -Path $script:ExplorerAdvancedKey -Name 'HideFileExt' -Value ([int]$snap.PreviousValue)
    return $true
}

# --- Tweak: Hidden files visibility ----------------------------------------------------
function Get-HiddenFilesState {
    $v = Get-RegistryTweakValue -Path $script:ExplorerAdvancedKey -Name 'Hidden' -DefaultIfMissing 2
    return [pscustomobject]@{ TweakId='HiddenFiles'; Current = if ($v -eq 1) {'Shown'} else {'Hidden'}; Recommended='Hidden (technician toggles as needed)'; Risk='SAFE' }
}
function Set-HiddenFilesShown {
    param([bool]$Show)
    $old = Get-RegistryTweakValue -Path $script:ExplorerAdvancedKey -Name 'Hidden' -DefaultIfMissing 2
    Save-TweakSnapshot -TweakId 'HiddenFiles' -PreviousValue $old | Out-Null
    Set-RegistryTweakValue -Path $script:ExplorerAdvancedKey -Name 'Hidden' -Value (if ($Show) {1} else {2})
}
function Restore-HiddenFilesState {
    $snap = Get-LatestTweakSnapshot -TweakId 'HiddenFiles'
    if (-not $snap) { return $false }
    Set-RegistryTweakValue -Path $script:ExplorerAdvancedKey -Name 'Hidden' -Value ([int]$snap.PreviousValue)
    return $true
}

# --- Tweak: Taskbar search box mode ----------------------------------------------------
$script:SearchKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'

function Get-TaskbarSearchState {
    $v = Get-RegistryTweakValue -Path $script:SearchKey -Name 'SearchboxTaskbarMode' -DefaultIfMissing 2
    $desc = switch ([int]$v) { 0 {'Hidden'} 1 {'Icon only'} default {'Search box'} }
    return [pscustomobject]@{ TweakId='TaskbarSearch'; Current = $desc; Recommended='Icon only (saves taskbar space)'; Risk='SAFE' }
}
function Set-TaskbarSearchMode {
    param([ValidateSet(0,1,2)][int]$Mode)
    $old = Get-RegistryTweakValue -Path $script:SearchKey -Name 'SearchboxTaskbarMode' -DefaultIfMissing 2
    Save-TweakSnapshot -TweakId 'TaskbarSearch' -PreviousValue $old | Out-Null
    Set-RegistryTweakValue -Path $script:SearchKey -Name 'SearchboxTaskbarMode' -Value $Mode
}
function Restore-TaskbarSearchState {
    $snap = Get-LatestTweakSnapshot -TweakId 'TaskbarSearch'
    if (-not $snap) { return $false }
    Set-RegistryTweakValue -Path $script:SearchKey -Name 'SearchboxTaskbarMode' -Value ([int]$snap.PreviousValue)
    return $true
}

# --- Tweak: Task View button ------------------------------------------------------------
function Get-TaskViewButtonState {
    $v = Get-RegistryTweakValue -Path $script:ExplorerAdvancedKey -Name 'ShowTaskViewButton' -DefaultIfMissing 1
    return [pscustomobject]@{ TweakId='TaskViewButton'; Current = if ($v -eq 1) {'Shown'} else {'Hidden'}; Recommended='Technician preference'; Risk='SAFE' }
}
function Set-TaskViewButtonShown {
    param([bool]$Show)
    $old = Get-RegistryTweakValue -Path $script:ExplorerAdvancedKey -Name 'ShowTaskViewButton' -DefaultIfMissing 1
    Save-TweakSnapshot -TweakId 'TaskViewButton' -PreviousValue $old | Out-Null
    Set-RegistryTweakValue -Path $script:ExplorerAdvancedKey -Name 'ShowTaskViewButton' -Value ([int]$Show)
}
function Restore-TaskViewButtonState {
    $snap = Get-LatestTweakSnapshot -TweakId 'TaskViewButton'
    if (-not $snap) { return $false }
    Set-RegistryTweakValue -Path $script:ExplorerAdvancedKey -Name 'ShowTaskViewButton' -Value ([int]$snap.PreviousValue)
    return $true
}

# --- Tweak: Windows Consumer Features / suggestions ------------------------------------
$script:CloudContentKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'

function Get-ConsumerFeaturesState {
    $v = Get-RegistryTweakValue -Path $script:CloudContentKey -Name 'DisableWindowsConsumerFeatures' -DefaultIfMissing 0
    return [pscustomobject]@{ TweakId='ConsumerFeatures'; Current = if ($v -eq 1) {'Disabled'} else {'Enabled'}; Recommended='Disabled (fewer suggested apps/ads)'; Risk='LOW' }
}
function Set-ConsumerFeaturesDisabled {
    param([bool]$Disable)
    $old = Get-RegistryTweakValue -Path $script:CloudContentKey -Name 'DisableWindowsConsumerFeatures' -DefaultIfMissing 0
    Save-TweakSnapshot -TweakId 'ConsumerFeatures' -PreviousValue $old | Out-Null
    Set-RegistryTweakValue -Path $script:CloudContentKey -Name 'DisableWindowsConsumerFeatures' -Value ([int]$Disable)
}
function Restore-ConsumerFeaturesState {
    $snap = Get-LatestTweakSnapshot -TweakId 'ConsumerFeatures'
    if (-not $snap) { return $false }
    Set-RegistryTweakValue -Path $script:CloudContentKey -Name 'DisableWindowsConsumerFeatures' -Value ([int]$snap.PreviousValue)
    return $true
}

# A small, honest registry (not a full declarative GUI-generation engine) describing each
# tweak so the GUI and -ApplyTweaks/-RestoreTweaks can loop over them generically.
function Get-TweakCatalog {
    return @(
        @{ Id='FileExtensions'; Name='Show file extensions'; Get={Get-FileExtensionsState}; Apply={Set-FileExtensionsShown -Show $true}; Restore={Restore-FileExtensionsState} }
        @{ Id='HiddenFiles'; Name='Show hidden files'; Get={Get-HiddenFilesState}; Apply={Set-HiddenFilesShown -Show $true}; Restore={Restore-HiddenFilesState} }
        @{ Id='TaskbarSearch'; Name='Taskbar search: icon only'; Get={Get-TaskbarSearchState}; Apply={Set-TaskbarSearchMode -Mode 1}; Restore={Restore-TaskbarSearchState} }
        @{ Id='TaskViewButton'; Name='Hide Task View button'; Get={Get-TaskViewButtonState}; Apply={Set-TaskViewButtonShown -Show $false}; Restore={Restore-TaskViewButtonState} }
        @{ Id='ConsumerFeatures'; Name='Disable Windows suggestions/ads'; Get={Get-ConsumerFeaturesState}; Apply={Set-ConsumerFeaturesDisabled -Disable $true}; Restore={Restore-ConsumerFeaturesState} }
    )
}

function Invoke-WindowsTweaksHeadless {
    if ($ApplyTweaks) {
        foreach ($id in $ApplyTweaks) {
            $entry = Get-TweakCatalog | Where-Object { $_.Id -eq $id }
            if (-not $entry) { Write-Log ('Unknown tweak id: ' + $id) 'Warning'; continue }
            if ($WhatIf) {
                Add-Result (New-Result 'WindowsConfig' ('Apply tweak: ' + $entry.Name) 'Skipped' -Skipped:$true -Message 'WhatIf: no change made.')
                continue
            }
            try {
                & $entry.Apply
                Add-Result (New-Result 'WindowsConfig' ('Apply tweak: ' + $entry.Name) 'Succeeded' -Changed:$true)
                Add-Change -Action 'Apply tweak' -Target $entry.Name -Result 'Succeeded' -Changed:$true -RiskLevel 'LOW'
            } catch {
                Add-Result (New-Result 'WindowsConfig' ('Apply tweak: ' + $entry.Name) 'Failed' -Errors @($_.Exception.Message))
            }
        }
    }
    if ($RestoreTweaks) {
        foreach ($id in $RestoreTweaks) {
            $entry = Get-TweakCatalog | Where-Object { $_.Id -eq $id }
            if (-not $entry) { Write-Log ('Unknown tweak id: ' + $id) 'Warning'; continue }
            if ($WhatIf) {
                Add-Result (New-Result 'WindowsConfig' ('Restore tweak: ' + $entry.Name) 'Skipped' -Skipped:$true -Message 'WhatIf: no change made.')
                continue
            }
            $ok = & $entry.Restore
            $status = if ($ok) {'Succeeded'} else {'NotApplicable'}
            Add-Result (New-Result 'WindowsConfig' ('Restore tweak: ' + $entry.Name) $status -Changed:$ok `
                -Message $(if (-not $ok) {'No prior snapshot was found for this tweak.'} else {''}))
        }
    }
}
#endregion

function Invoke-WindowsConfig {
    $cfg = [ordered]@{}
    $cfg.PowerPlan = try { (powercfg /getactivescheme 2>&1 | Out-String).Trim() } catch { '' }
    $cfg.Time = try { (w32tm /query /status 2>&1 | Out-String).Trim() } catch { '' }
    $cfg.WinRE = try { (reagentc /info 2>&1 | Out-String).Trim() } catch { '' }
    $cfg.BCD = try { (bcdedit /enum '{current}' 2>&1 | Out-String).Trim() } catch { '' }
    $cfg.Firewall = try { (Get-NetFirewallProfile -ErrorAction Stop | Select-Object Name,Enabled,DefaultInboundAction,DefaultOutboundAction) } catch { @() }
    Add-Result (New-Result 'WindowsConfig' 'Windows configuration audit' 'Succeeded' `
        -Details $cfg -Message 'Power plan, time sync, WinRE, BCD and firewall configuration inspected.')
}

function Invoke-Restore {
    $sr = Get-Command Enable-ComputerRestore -ErrorAction SilentlyContinue
    $points = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue)
    Add-Result (New-Result 'Restore' 'System Restore availability' `
        $(if($sr){'Succeeded'}else{'NotApplicable'}) -Details $points `
        -Message $(if($sr){'System Restore cmdlet is available; no restore point was created or restored.'}else{'System Restore cmdlets are unavailable.'}))
}

function Invoke-RebootResume {
    $pending = $script:State.RebootRequired
    if ($pending) {
        Add-Result (New-Result 'RebootResume' 'Reboot state' 'RequiresReboot' `
            -Reboot:$true -RequiresTechnician:$true `
            -Message 'A reboot is indicated by Windows/tool state. Toolkit will not reboot automatically.')
        if (-not $NoReboot -and -not $Unattended) {
            Write-Log 'A reboot is recommended, but automatic reboot is disabled by design.' 'Warning'
        }
    } else {
        Add-Result (New-Result 'RebootResume' 'Reboot state' 'Succeeded' `
            -Message 'No pending reboot was detected by the checks performed.')
    }
}

function Invoke-Verification {
    $failed = @($script:Results | Where-Object {$_.Status -eq 'Failed'})
    $critical = @($script:Findings | Where-Object {$_.Severity -eq 'Critical'})
    $high = @($script:Findings | Where-Object {$_.Severity -eq 'High'})
    $medium = @($script:Findings | Where-Object {$_.Severity -eq 'Medium'})

    if ($critical.Count -gt 0) {
        $script:OverallStatus = 'NEEDS ATTENTION'
    } elseif ($failed.Count -gt 0 -or $high.Count -gt 0 -or $medium.Count -gt 0) {
        $script:OverallStatus = 'HEALTHY WITH WARNINGS'
    } else {
        $script:OverallStatus = 'HEALTHY'
    }

    Add-Result (New-Result 'Verification' 'Run verification' 'Succeeded' `
        -Details ([pscustomobject]@{
            FailedResults=$failed.Count
            CriticalFindings=$critical.Count
            HighFindings=$high.Count
            MediumFindings=$medium.Count
            OverallStatus=$script:OverallStatus
        }) -Message ('Overall status: ' + $script:OverallStatus))
}

function Invoke-Stage {
    param([string]$Name,[scriptblock]$Action)
    $script:State.CurrentStage = $Name
    Write-State
    Write-Log ("--- Stage: {0} ---" -f $Name) 'Info'
    try {
        & $Action
        if ($script:State.CompletedStages -notcontains $Name) {
            $script:State.CompletedStages += $Name
        }
        Write-Log ("Stage {0} completed." -f $Name) 'Success'
    } catch {
        if ($script:State.FailedStages -notcontains $Name) {
            $script:State.FailedStages += $Name
        }
        Add-Result (New-Result $Name 'Stage execution' 'Failed' -Severity 'High' `
            -Message 'Unhandled stage exception.' -Errors @($_.Exception.Message))
        Write-Log ("Stage {0} failed: {1}" -f $Name,$_.Exception.Message) 'Error'
    }
    Write-State
}

function Get-StageOrder {
    return @(
        'Preflight','Audit','Backup','Hardware','Storage','Security','EventLogs',
        'Performance','Repair','Cleanup','Network','Drivers','WindowsUpdate',
        'Debloat','Applications','WindowsConfig','Restore','RebootResume',
        'Verification','Finalize','FinalReport'
    )
}

function Get-StageAction {
    param([string]$Name)
    switch ($Name) {
        'Preflight'     { return { Invoke-Preflight } }
        'Audit'         { return { Invoke-Audit } }
        'Backup'        { return { Invoke-Backup } }
        'Hardware'      { return { Invoke-Hardware } }
        'Storage'       { return { Invoke-Storage } }
        'Security'      { return { Invoke-Security } }
        'EventLogs'     { return { Invoke-EventLogs } }
        'Performance'   { return { Invoke-Performance } }
        'Repair'        { return { Invoke-SystemRepair } }
        'Cleanup'       { return { Invoke-Cleanup } }
        'Network'       { return { Invoke-Network } }
        'Drivers'       { return { Invoke-Drivers } }
        'WindowsUpdate' { return { Invoke-WindowsUpdate } }
        'Debloat'       { return { Invoke-Debloat } }
        'Applications'  { return { Invoke-Applications } }
        'WindowsConfig' { return { Invoke-WindowsConfig } }
        'Restore'       { return { Invoke-Restore } }
        'TechTools'     { return { Invoke-TechToolsStage } }
        'AppCatalog'    { return { Invoke-AppCatalogStage } }
        'RebootResume'  { return { Invoke-RebootResume } }
        'Verification'  { return { Invoke-Verification } }
        'Finalize'      { return { Invoke-Finalize } }
        'FinalReport'   { return { Invoke-FinalReport } }
        default         { return $null }
    }
}

function Invoke-Preflight {
    if (-not $script:Toolkit.IsElevated) {
        throw 'Administrator privileges are required after the elevation handoff.'
    }
    $script:Toolkit.IsElevated = Test-IsAdministrator
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    Add-Result (New-Result 'Preflight' 'Execution environment' 'Succeeded' `
        -Details ([pscustomobject]@{
            Administrator=$script:Toolkit.IsElevated
            PowerShell=$PSVersionTable.PSVersion.ToString()
            OS=$os.Caption
            Build=$os.BuildNumber
            OfflineMode=[bool]$OfflineMode
            WhatIf=[bool]$WhatIf
        }) -Message 'Preflight checks passed.')
    [void](Test-InternetConnectivity)
}

function Invoke-Finalize {
    $script:State.EndUtc = Get-UtcString
    $script:State.Status = 'Completed'
    $script:State.CurrentStage = ''
    $script:State.RebootRequired = $script:RebootRequired
    Write-State
    Add-Result (New-Result 'Finalize' 'Run finalization' 'Succeeded' `
        -Message 'Run state finalized. Reports are generated by FinalReport.')
}

function Escape-Html {
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Get-FindingStatus {
    $critical = @($script:Findings | Where-Object {$_.Severity -eq 'Critical'}).Count
    $high = @($script:Findings | Where-Object {$_.Severity -eq 'High'}).Count
    $medium = @($script:Findings | Where-Object {$_.Severity -eq 'Medium'}).Count
    if ($critical -gt 0 -or $high -gt 0) { return 'NEEDS ATTENTION' }
    if ($medium -gt 0 -or @($script:Results | Where-Object {$_.Status -eq 'Failed'}).Count -gt 0) {
        return 'HEALTHY WITH WARNINGS'
    }
    return 'HEALTHY'
}

function Generate-Reports {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $base = Join-Path $script:Paths.Reports ('WoodvillePC_{0}_{1}' -f $env:COMPUTERNAME,$stamp)
    $json = $base + '.json'
    $csv = $base + '.csv'
    $html = $base + '.html'
    $status = Get-FindingStatus
    $script:OverallStatus = $status

    $bundle = [ordered]@{
        SchemaVersion = 1
        Toolkit = $script:Toolkit
        Run = $script:State
        Results = @($script:Results)
        Findings = @($script:Findings)
        Changes = @($script:Changes)
        Backups = @($script:Backups)
        Artifacts = @($script:Artifacts)
        OverallStatus = $status
        GeneratedUtc = Get-UtcString
    }

    if ($script:Config.ReportSettings.WriteJson) {
        Write-AtomicText -Path $json -Content (ConvertTo-JsonSafe $bundle)
        Add-Artifact -Path $json -Type 'ReportJSON' -Description 'Structured run report'
    }

    if ($script:Config.ReportSettings.WriteCsv) {
        $rows = @($script:Results | Select-Object RunId,Stage,Task,Status,Severity,Changed,Skipped,ExitCode,Message,RebootRequired,RequiresTechnician,RiskLevel,Tool,ToolVersion)
        if ($rows.Count -gt 0) {
            $rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
        } else {
            Write-AtomicText -Path $csv -Content "RunId,Stage,Task,Status`r`n"
        }
        Add-Artifact -Path $csv -Type 'ReportCSV' -Description 'Task results CSV'
    }

    if ($script:Config.ReportSettings.WriteHtml) {
        $findingRows = @($script:Findings | ForEach-Object {
            '<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td></tr>' -f `
                (Escape-Html $_.Category),(Escape-Html $_.Severity),(Escape-Html $_.Description),
                (Escape-Html $_.Evidence),(Escape-Html $_.RecommendedAction)
        }) -join [Environment]::NewLine

        $resultRows = @($script:Results | ForEach-Object {
            '<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td></tr>' -f `
                (Escape-Html $_.Stage),(Escape-Html $_.Task),(Escape-Html $_.Status),
                (Escape-Html $_.Changed),(Escape-Html $_.Message)
        }) -join [Environment]::NewLine

        $client = Escape-Html $ClientName
        $ticket = Escape-Html $TicketNumber
        $tech = Escape-Html $TechName
        $issue = Escape-Html $ReportedIssue

        $branding = Get-CompanyBranding
        $logoImgTag = if ($branding.LogoDataUri) { '<img src="' + $branding.LogoDataUri + '" alt="logo" class="logo"/>' } else { '' }

        # Precomputed (not inlined) because "@(...)" is NOT a valid interpolation trigger
        # inside a double-quoted here-string - it prints as literal text, not a value.
        # Only "$(...)" and "$variable" interpolate. Counting these ahead of time avoids
        # that trap entirely.
        $critCount = @($script:Findings | Where-Object { $_.Severity -eq 'Critical' }).Count
        $highCount = @($script:Findings | Where-Object { $_.Severity -eq 'High' }).Count
        $medCount  = @($script:Findings | Where-Object { $_.Severity -eq 'Medium' }).Count
        $lowCount  = @($script:Findings | Where-Object { $_.Severity -eq 'Low' }).Count

        $page = @"
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>$(Escape-Html $branding.Name) - $([System.Net.WebUtility]::HtmlEncode($env:COMPUTERNAME))</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;background:#f3f5f7;margin:0;color:#222}
main{max-width:1250px;margin:30px auto;background:#fff;padding:30px;box-shadow:0 2px 14px #bbb}
header{border-bottom:4px solid #1b5e9e;padding-bottom:18px;display:flex;align-items:center;gap:18px}
header img.logo{height:56px;border-radius:6px}
h1{margin:0}.status{display:inline-block;padding:8px 14px;margin-top:10px;border-radius:5px;font-weight:700}
table{width:100%;border-collapse:collapse;margin:12px 0 28px}
th{background:#1b5e9e;color:#fff;text-align:left;padding:9px}
td{border-bottom:1px solid #ddd;padding:8px;vertical-align:top}
small{color:#666}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px}
.card{background:#f1f4f7;padding:15px;border-radius:5px}.num{font-size:24px;font-weight:700}
</style>
</head>
<body><main>
<header>
$logoImgTag
<div>
<h1>$(Escape-Html $branding.Name)</h1>
<p>$(Escape-Html $branding.Tagline)</p>
<div class="status">$([System.Net.WebUtility]::HtmlEncode($status))</div>
</div>
</header>
<h2>Run Summary</h2>
<table>
<tr><th>Run ID</th><td>$([System.Net.WebUtility]::HtmlEncode($script:RunId))</td></tr>
<tr><th>Computer</th><td>$([System.Net.WebUtility]::HtmlEncode($env:COMPUTERNAME))</td></tr>
<tr><th>Client</th><td>$client</td></tr>
<tr><th>Ticket</th><td>$ticket</td></tr>
<tr><th>Technician</th><td>$tech</td></tr>
<tr><th>Reported Issue</th><td>$issue</td></tr>
<tr><th>WhatIf</th><td>$([bool]$WhatIf)</td></tr>
<tr><th>Reboot Required</th><td>$([bool]$script:RebootRequired)</td></tr>
</table>
<h2>Findings</h2>
<div class="grid">
<div class="card"><div class="num">$critCount</div>Critical</div>
<div class="card"><div class="num">$highCount</div>High</div>
<div class="card"><div class="num">$medCount</div>Medium</div>
<div class="card"><div class="num">$lowCount</div>Low</div>
</div>
<table><tr><th>Category</th><th>Severity</th><th>Description</th><th>Evidence</th><th>Recommended Action</th></tr>
$findingRows
</table>
<h2>Task Results</h2>
<table><tr><th>Stage</th><th>Task</th><th>Status</th><th>Changed</th><th>Message</th></tr>
$resultRows
</table>
<footer><small>Generated $([System.Net.WebUtility]::HtmlEncode((Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) | Toolkit $([System.Net.WebUtility]::HtmlEncode($script:Toolkit.Version)) | No passwords, tokens, private keys or BitLocker recovery keys are intentionally collected by this report.</small></footer>
</main></body></html>
"@
        Write-AtomicText -Path $html -Content $page
        Add-Artifact -Path $html -Type 'ReportHTML' -Description 'Technician/customer-safe HTML report'
    }

    return [pscustomobject]@{JSON=$json;CSV=$csv;HTML=$html;Status=$status}
}

function Invoke-FinalReport {
    $reports = Generate-Reports
    Add-Result (New-Result 'FinalReport' 'Generate reports' 'Succeeded' `
        -ArtifactPaths @($reports.JSON,$reports.CSV,$reports.HTML) `
        -Message ('Reports generated. Overall status: ' + $reports.Status))
}

function Show-Banner {
    Clear-Host
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' WOODVILLE PC & TECH - PC TOOLKIT v11.4' -ForegroundColor Cyan
    Write-Host ' Diagnostics | Repair | Maintenance | Recovery' -ForegroundColor White
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host (' Run ID: {0}' -f $script:RunId) -ForegroundColor DarkGray
    Write-Host ''
}

function Show-Help {
    Write-Host @'
WOODVILLE PC TOOLKIT v11.4

Examples:
  .\WoodvillePCToolkit.ps1
  .\WoodvillePCToolkit.ps1 -Gui
  .\WoodvillePCToolkit.ps1 -Stage Audit
  .\WoodvillePCToolkit.ps1 -Stage Audit,Hardware,Storage
  .\WoodvillePCToolkit.ps1 -Stage All
  .\WoodvillePCToolkit.ps1 -Stage Repair -WhatIf
  .\WoodvillePCToolkit.ps1 -Stage Audit -OfflineMode
  .\WoodvillePCToolkit.ps1 -ApplyTweaks FileExtensions,ConsumerFeatures
  .\WoodvillePCToolkit.ps1 -RestoreTweaks FileExtensions

Safety:
  - Administrator elevation is handled by the script; #Requires is intentionally not used.
  - WhatIf prevents repair/cleanup/tweak/install execution and reports what would happen.
  - Unattended means no interaction; it does not authorize risky changes.
  - SDIO and WSUS Offline are detected always, but only actually RUN when the matching
    Safety.AllowDriverInstall / Safety.AllowWindowsUpdateRepair flag in Config\Toolkit.json
    is set to true (default: false, off). SDIO always hands off to its own GUI for the
    technician to pick drivers - this toolkit never silently installs one.
  - AppX debloat removal only runs when Safety.AllowDebloatChanges is true (default: false).
  - Reboots are never automatic.
  - Optional security tools are never downloaded from a guessed location.
  - Cleanup is limited to old files in approved temp locations.
  - Windows Tweaks are reversible: every Apply saves a snapshot; Restore reapplies the
    last saved value for that tweak.
  - -Gui launches a WPF interface over this same engine. GUI-triggered work always runs
    as a separate -Unattended subprocess of this exact script (same code path as the CLI,
    same Safety.Allow* gating) - the GUI itself never modifies the system directly except
    for saving Config\Toolkit.json from the Settings page.

Stages:
  Preflight Audit Backup Hardware Storage Security EventLogs Performance
  Repair Cleanup Network Drivers WindowsUpdate Debloat Applications
  WindowsConfig Restore TechTools AppCatalog RebootResume Verification Finalize FinalReport
  All

  Note: TechTools and AppCatalog are interactive and are intentionally excluded
  from "All" and from the default Unattended stage list - request them
  explicitly with -Stage TechTools / -Stage AppCatalog when running interactively.
  AppCatalog lets you pick software to install via winget from a curated list in
  Config\AppCatalog.json (editable - add or remove entries freely).

Windows Tweaks (Get/Set/Restore, Sophia-style):
  FileExtensions HiddenFiles TaskbarSearch TaskViewButton ConsumerFeatures
  Use -ApplyTweaks / -RestoreTweaks with a comma-separated list of the above,
  or manage them from the GUI's "Windows Tweaks" page.

Files:
  Config\Toolkit.json
  Config\AppCatalog.json
  Backups\<RunId>\
  Backups\<RunId>\Tweaks\
  Logs\
  Reports\
  State\RunState.json
  Cache\
'@
}

function Get-TechnicianToolsList {
    return @(
        @{N='Event Viewer';P='eventvwr.msc'},
        @{N='Device Manager';P='devmgmt.msc'},
        @{N='Disk Management';P='diskmgmt.msc'},
        @{N='Computer Management';P='compmgmt.msc'},
        @{N='Services';P='services.msc'},
        @{N='Task Scheduler';P='taskschd.msc'},
        @{N='Registry Editor';P='regedit.exe'},
        @{N='System Properties';P='sysdm.cpl'},
        @{N='Network Connections';P='ncpa.cpl'},
        @{N='Windows Security';P='windowsdefender:'},
        @{N='Reliability Monitor';P='perfmon.exe';A='/rel'},
        @{N='Resource Monitor';P='resmon.exe'},
        @{N='System Information';P='msinfo32.exe'},
        @{N='Control Panel';P='control.exe'},
        @{N='PowerShell';P='powershell.exe'},
        @{N='Command Prompt';P='cmd.exe'}
    )
}

function Show-TechnicianTools {
    $tools = Get-TechnicianToolsList
    while ($true) {
        Clear-Host
        Write-Host 'TECHNICIAN TOOL CENTER' -ForegroundColor Cyan
        for ($i=0; $i -lt $tools.Count; $i++) {
            Write-Host (' {0}. {1}' -f ($i+1),$tools[$i].N)
        }
        Write-Host ' 0. Back'
        $c = Read-Host 'Select'
        if ($c -eq '0') { return }
        $n = 0
        if ([int]::TryParse($c,[ref]$n) -and $n -ge 1 -and $n -le $tools.Count) {
            $t = $tools[$n-1]
            try {
                if ($t.A) { Start-Process -FilePath $t.P -ArgumentList $t.A }
                else { Start-Process -FilePath $t.P }
            } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Start-Sleep 2 }
        }
    }
}

function Invoke-TechToolsStage {
    # TechTools is interactive (Read-Host driven) - never block an unattended run on it.
    if ($Unattended) {
        Add-Result (New-Result 'TechTools' 'Technician Tool Center' 'Skipped' -Skipped:$true `
            -Message 'Skipped: TechTools is interactive and Unattended was requested.')
        return
    }
    Add-Result (New-Result 'TechTools' 'Technician Tool Center' 'Succeeded' `
        -Message 'Technician Tool Center opened interactively.')
    Show-TechnicianTools
}

function Show-InteractiveMenu {
    while ($true) {
        Show-Banner
        Write-Host '1. Full diagnostic + safe repair workflow'
        Write-Host '2. Audit / diagnostics only'
        Write-Host '3. Repair (with backup)'
        Write-Host '4. Security'
        Write-Host '5. Cleanup'
        Write-Host '6. Custom stages'
        Write-Host '7. Technician Tool Center'
        Write-Host '8. Help'
        Write-Host '9. Application Catalog (install common software via winget)'
        Write-Host '0. Exit'
        $choice = Read-Host 'Selection'
        switch ($choice) {
            '1' { return (Get-StageOrder) }
            '2' { return @('Preflight','Audit','Hardware','Storage','Security','EventLogs','Performance','Network','Drivers','WindowsUpdate','Verification','FinalReport') }
            '3' { return @('Preflight','Audit','Backup','Repair','Verification','FinalReport') }
            '4' { return @('Preflight','Security','EventLogs','Verification','FinalReport') }
            '5' { return @('Preflight','Cleanup','Verification','FinalReport') }
            '6' {
                $raw = Read-Host 'Enter comma-separated stage names'
                return @($raw -split ',' | ForEach-Object {$_.Trim()} | Where-Object {$_})
            }
            '7' { Show-TechnicianTools }
            '8' { Show-Help; Read-Host 'Press ENTER' | Out-Null }
            '9' { Show-ApplicationCatalog }
            '0' { return @() }
            default { Write-Host 'Invalid selection.' -ForegroundColor Yellow; Start-Sleep 1 }
        }
    }
}

#region GUI (WPF)
function ConvertTo-BitmapImageFromBase64 {
    param([string]$Base64)
    try {
        $bytes = [Convert]::FromBase64String(($Base64 -replace '\s', ''))
        $ms = New-Object System.IO.MemoryStream(,$bytes)
        $img = New-Object System.Windows.Media.Imaging.BitmapImage
        $img.BeginInit()
        $img.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $img.StreamSource = $ms
        $img.EndInit()
        $img.Freeze()
        return $img
    } catch { return $null }
}

function Start-EngineSubprocess {
    # Every GUI-triggered action runs as a fresh, fully-independent invocation of THIS
    # SAME SCRIPT via -Stage/-InstallApps/-ApplyTweaks/-RestoreTweaks. It inherits the
    # GUI's own elevated token (no second UAC prompt), and always runs -Unattended since
    # there is no console for Read-Host confirmation prompts to appear on - destructive
    # actions are instead controlled by the Safety.Allow* flags on the Settings page.
    param([string[]]$ExtraArgs)
    $ps = (Get-Command powershell.exe -ErrorAction SilentlyContinue)
    if (-not $ps) { throw 'Windows PowerShell executable was not found.' }

    $allArgs = New-Object System.Collections.Generic.List[string]
    $allArgs.Add('-NoProfile'); $allArgs.Add('-ExecutionPolicy'); $allArgs.Add('Bypass')
    $allArgs.Add('-File'); $allArgs.Add($PSCommandPath)
    foreach ($a in $ExtraArgs) { $allArgs.Add($a) }
    $allArgs.Add('-Unattended')
    if ($script:GuiWhatIf) { $allArgs.Add('-WhatIf') }
    if ($script:GuiClientName)    { $allArgs.Add('-ClientName');    $allArgs.Add($script:GuiClientName) }
    if ($script:GuiTicketNumber)  { $allArgs.Add('-TicketNumber');  $allArgs.Add($script:GuiTicketNumber) }
    if ($script:GuiTechName)      { $allArgs.Add('-TechName');      $allArgs.Add($script:GuiTechName) }
    if ($script:GuiReportedIssue) { $allArgs.Add('-ReportedIssue'); $allArgs.Add($script:GuiReportedIssue) }

    $argString = ConvertTo-QuotedArgumentString -ArgumentList $allArgs.ToArray()
    return (Start-Process -FilePath $ps.Source -ArgumentList $argString -WindowStyle Hidden -PassThru)
}

function Show-MainGui {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

    $branding = Get-CompanyBranding
    $script:GuiWhatIf = $false
    $script:GuiClientName = ''
    $script:GuiTicketNumber = ''
    $script:GuiTechName = ''
    $script:GuiReportedIssue = ''
    $script:GuiCurrentProcess = $null
    $script:GuiLastLogPath = $null
    $script:GuiLastLogLength = 0

    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml/x"
        Title="Woodville PC Toolkit" Height="760" Width="1180"
        WindowStartupLocation="CenterScreen" Background="#FF1B1F27">
  <DockPanel LastChildFill="True">
    <Border DockPanel.Dock="Top" Background="#FF0C2340" Padding="14">
      <StackPanel Orientation="Horizontal">
        <Image x:Name="LogoImage" Height="42" Margin="0,0,14,0"/>
        <StackPanel VerticalAlignment="Center">
          <TextBlock x:Name="TitleText" Text="Woodville PC Toolkit" FontSize="20" FontWeight="Bold" Foreground="White"/>
          <TextBlock x:Name="SubtitleText" Text="Professional Windows Diagnostics, Repair &amp; Maintenance" FontSize="12" Foreground="#FF9FB3C8"/>
        </StackPanel>
      </StackPanel>
    </Border>

    <Border DockPanel.Dock="Bottom" Background="#FF11151C" Padding="8" BorderBrush="#FF2A3242" BorderThickness="0,1,0,0">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock x:Name="StatusText" Grid.Column="0" Text="Ready." Foreground="#FFB9C6D4" VerticalAlignment="Center"/>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <TextBlock x:Name="ComputerText" Foreground="#FF7D8FA1" Margin="0,0,14,0" VerticalAlignment="Center"/>
          <TextBlock x:Name="ElevatedText" Foreground="#FF7D8FA1" Margin="0,0,14,0" VerticalAlignment="Center"/>
          <CheckBox x:Name="ChkWhatIf" Content="Simulation Mode (WhatIf)" Foreground="#FFFFB74D" VerticalAlignment="Center"/>
        </StackPanel>
      </Grid>
    </Border>

    <Border DockPanel.Dock="Bottom" Background="Black" Height="150" BorderBrush="#FF2A3242" BorderThickness="0,1,0,0">
      <TextBox x:Name="LogBox" Background="Black" Foreground="#FF7FD0AF" FontFamily="Consolas" FontSize="11"
               IsReadOnly="True" TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
    </Border>

    <Border DockPanel.Dock="Left" Width="190" Background="#FF141922">
      <StackPanel Margin="8">
        <Button x:Name="BtnNavWorkflows" Content="Dashboard / Workflows" Margin="0,4" Padding="8"/>
        <Button x:Name="BtnNavTweaks" Content="Windows Tweaks" Margin="0,4" Padding="8"/>
        <Button x:Name="BtnNavApps" Content="Application Catalog" Margin="0,4" Padding="8"/>
        <Button x:Name="BtnNavTools" Content="Technician Tools" Margin="0,4" Padding="8"/>
        <Button x:Name="BtnNavReports" Content="Reports" Margin="0,4" Padding="8"/>
        <Button x:Name="BtnNavSettings" Content="Settings" Margin="0,4" Padding="8"/>
      </StackPanel>
    </Border>

    <Grid Margin="16">
      <Grid x:Name="PageWorkflows" Visibility="Visible">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <GroupBox Grid.Row="0" Header="Customer / Ticket Information" Foreground="White" Margin="0,0,0,10">
          <Grid Margin="6">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
            <TextBlock Text="Client:" Foreground="White" Grid.Row="0" Grid.Column="0" Margin="4" VerticalAlignment="Center"/>
            <TextBox x:Name="TxtClient" Grid.Row="0" Grid.Column="1" Margin="4"/>
            <TextBlock Text="Ticket #:" Foreground="White" Grid.Row="0" Grid.Column="2" Margin="4" VerticalAlignment="Center"/>
            <TextBox x:Name="TxtTicket" Grid.Row="0" Grid.Column="3" Margin="4"/>
            <TextBlock Text="Technician:" Foreground="White" Grid.Row="1" Grid.Column="0" Margin="4" VerticalAlignment="Center"/>
            <TextBox x:Name="TxtTech" Grid.Row="1" Grid.Column="1" Margin="4"/>
            <TextBlock Text="Reported Issue:" Foreground="White" Grid.Row="1" Grid.Column="2" Margin="4" VerticalAlignment="Center"/>
            <TextBox x:Name="TxtIssue" Grid.Row="1" Grid.Column="3" Margin="4"/>
          </Grid>
        </GroupBox>
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
          <StackPanel x:Name="WorkflowButtonsPanel"/>
        </ScrollViewer>
      </Grid>

      <Grid x:Name="PageTweaks" Visibility="Collapsed">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="Windows Tweaks (reversible - each has a Restore option)" Foreground="White" FontSize="15" Margin="0,0,0,8"/>
        <ListBox x:Name="TweaksList" Grid.Row="1" Background="#FF11151C" Foreground="White"/>
        <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,10,0,0">
          <Button x:Name="BtnRefreshTweaks" Content="Refresh States" Padding="8,4" Margin="0,0,8,0"/>
          <Button x:Name="BtnApplyTweaks" Content="Apply Selected" Padding="8,4" Margin="0,0,8,0"/>
          <Button x:Name="BtnRestoreTweaks" Content="Restore Selected" Padding="8,4"/>
        </StackPanel>
      </Grid>

      <Grid x:Name="PageApps" Visibility="Collapsed">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="Application Catalog (installs via winget - nothing installs until you click Install)" Foreground="White" FontSize="15" Margin="0,0,0,8"/>
        <ListBox x:Name="AppsList" Grid.Row="1" Background="#FF11151C" Foreground="White"/>
        <Button x:Name="BtnInstallApps" Grid.Row="2" Content="Install Selected" Padding="8,4" Margin="0,10,0,0" HorizontalAlignment="Left"/>
      </Grid>

      <Grid x:Name="PageTools" Visibility="Collapsed">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="Technician Tool Center" Foreground="White" FontSize="15" Margin="0,0,0,8"/>
        <ScrollViewer Grid.Row="1"><WrapPanel x:Name="ToolsPanel"/></ScrollViewer>
      </Grid>

      <Grid x:Name="PageReports" Visibility="Collapsed">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="Reports" Foreground="White" FontSize="15" Margin="0,0,0,8"/>
        <ListBox x:Name="ReportsList" Grid.Row="1" Background="#FF11151C" Foreground="White"/>
        <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,10,0,0">
          <Button x:Name="BtnOpenReport" Content="Open Selected" Padding="8,4" Margin="0,0,8,0"/>
          <Button x:Name="BtnOpenReportsFolder" Content="Open Reports Folder" Padding="8,4"/>
        </StackPanel>
      </Grid>

      <Grid x:Name="PageSettings" Visibility="Collapsed">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="4">
            <TextBlock Text="Branding" Foreground="White" FontSize="15" Margin="0,0,0,6"/>
            <TextBlock Text="Company Name" Foreground="#FFB9C6D4"/>
            <TextBox x:Name="TxtCompanyName" Margin="0,2,0,8"/>
            <TextBlock Text="Company Tagline" Foreground="#FFB9C6D4"/>
            <TextBox x:Name="TxtCompanyTagline" Margin="0,2,0,8"/>
            <TextBlock Text="Logo Path (blank = use built-in logo)" Foreground="#FFB9C6D4"/>
            <TextBox x:Name="TxtLogoPath" Margin="0,2,0,14"/>
            <TextBlock Text="Tool Paths" Foreground="White" FontSize="15" Margin="0,0,0,6"/>
            <TextBlock Text="SDIO Path" Foreground="#FFB9C6D4"/>
            <TextBox x:Name="TxtSDIOPath" Margin="0,2,0,8"/>
            <TextBlock Text="WSUS Offline Path" Foreground="#FFB9C6D4"/>
            <TextBox x:Name="TxtWSUSPath" Margin="0,2,0,14"/>
            <TextBlock Text="Safety (all default OFF - detection/diagnostics still always run)" Foreground="White" FontSize="15" Margin="0,0,0,6"/>
            <CheckBox x:Name="ChkAllowDriverInstall" Content="Allow SDIO to update its driver-pack index and launch its GUI" Foreground="White" Margin="0,2"/>
            <CheckBox x:Name="ChkAllowWindowsUpdateRepair" Content="Allow WSUS Offline to actually run" Foreground="White" Margin="0,2"/>
            <CheckBox x:Name="ChkAllowDebloatChanges" Content="Allow AppX debloat removal" Foreground="White" Margin="0,2"/>
            <CheckBox x:Name="ChkAllowNetworkReset" Content="Allow network stack reset actions" Foreground="White" Margin="0,2"/>
            <CheckBox x:Name="ChkAllowReboot" Content="Allow automatic reboot prompts to default to Reboot Now" Foreground="White" Margin="0,2"/>
            <Button x:Name="BtnSaveSettings" Content="Save Settings" Padding="10,6" Margin="0,16,0,0" HorizontalAlignment="Left"/>
          </StackPanel>
        </ScrollViewer>
      </Grid>
    </Grid>
  </DockPanel>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $logo = ConvertTo-BitmapImageFromBase64 -Base64 ($branding.LogoDataUri -replace '^data:image/[a-zA-Z]+;base64,','')
    if ($logo) { $window.FindName('LogoImage').Source = $logo }
    $window.FindName('TitleText').Text = $branding.Name
    $window.FindName('SubtitleText').Text = $branding.Tagline
    $window.FindName('ComputerText').Text = 'Computer: ' + $env:COMPUTERNAME
    $window.FindName('ElevatedText').Text = if ($script:Toolkit.IsElevated) { 'Elevated: Yes' } else { 'Elevated: No' }

    $pages = @{
        Workflows = $window.FindName('PageWorkflows')
        Tweaks    = $window.FindName('PageTweaks')
        Apps      = $window.FindName('PageApps')
        Tools     = $window.FindName('PageTools')
        Reports   = $window.FindName('PageReports')
        Settings  = $window.FindName('PageSettings')
    }
    function Show-GuiPage {
        param([string]$Name)
        foreach ($key in $pages.Keys) {
            $pages[$key].Visibility = if ($key -eq $Name) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }
        }
    }
    $window.FindName('BtnNavWorkflows').Add_Click({ Show-GuiPage -Name 'Workflows' })
    $window.FindName('BtnNavTweaks').Add_Click({ Show-GuiPage -Name 'Tweaks'; Update-TweaksList })
    $window.FindName('BtnNavApps').Add_Click({ Show-GuiPage -Name 'Apps' })
    $window.FindName('BtnNavTools').Add_Click({ Show-GuiPage -Name 'Tools' })
    $window.FindName('BtnNavReports').Add_Click({ Show-GuiPage -Name 'Reports'; Update-ReportsList })
    $window.FindName('BtnNavSettings').Add_Click({ Show-GuiPage -Name 'Settings' })

    $logBox = $window.FindName('LogBox')
    $statusText = $window.FindName('StatusText')

    $txtClient = $window.FindName('TxtClient'); $txtTicket = $window.FindName('TxtTicket')
    $txtTech = $window.FindName('TxtTech'); $txtIssue = $window.FindName('TxtIssue')
    $chkWhatIf = $window.FindName('ChkWhatIf')

    $allButtons = New-Object System.Collections.Generic.List[object]

    function Set-GuiBusy {
        param([bool]$Busy)
        foreach ($b in $allButtons) { $b.IsEnabled = (-not $Busy) }
    }

    function Start-GuiWorkflow {
        param([string[]]$ExtraArgs, [string]$Label)
        $script:GuiClientName = $txtClient.Text; $script:GuiTicketNumber = $txtTicket.Text
        $script:GuiTechName = $txtTech.Text; $script:GuiReportedIssue = $txtIssue.Text
        $script:GuiWhatIf = [bool]$chkWhatIf.IsChecked
        $logBox.Text = ''
        $script:GuiLastLogLength = 0
        $statusText.Text = 'Running: ' + $Label + ' ...'
        Set-GuiBusy -Busy $true
        try {
            $script:GuiCurrentProcess = Start-EngineSubprocess -ExtraArgs $ExtraArgs
        } catch {
            $statusText.Text = 'Failed to start: ' + $_.Exception.Message
            Set-GuiBusy -Busy $false
            return
        }
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(500)
        $timer.Add_Tick({
            try {
                $newest = Get-ChildItem -Path $script:Paths.Logs -Filter 'Run_*.log' -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
                if ($newest) {
                    $text = Get-Content -LiteralPath $newest.FullName -Raw -ErrorAction SilentlyContinue
                    if ($text -and $text.Length -ne $script:GuiLastLogLength) {
                        $logBox.Text = $text
                        $logBox.ScrollToEnd()
                        $script:GuiLastLogLength = $text.Length
                    }
                }
            } catch {}
            if ($script:GuiCurrentProcess -and $script:GuiCurrentProcess.HasExited) {
                $timer.Stop()
                $statusText.Text = $Label + ' finished.'
                Set-GuiBusy -Busy $false
                Update-ReportsList
            }
        })
        $timer.Start()
    }

    # ---- Workflows page: one-click bundles (section 7) ----
    $workflowPanel = $window.FindName('WorkflowButtonsPanel')
    $workflows = @(
        @{ Label='Full Diagnostic (read-only)'; Risk='SAFE'; Stages=@('Preflight','Audit','Hardware','Storage','Security','EventLogs','Performance','Network','Drivers','WindowsUpdate','Verification','FinalReport') }
        @{ Label='Full Repair (with backup first)'; Risk='MODERATE'; Stages=@('Preflight','Audit','Backup','Hardware','Storage','Security','Repair','WindowsUpdate','Network','Drivers','Cleanup','Verification','FinalReport') }
        @{ Label='Diagnose Only'; Risk='SAFE'; Stages=@('Preflight','Audit','Hardware','Storage','Security','EventLogs','Verification','FinalReport') }
        @{ Label='Safe Maintenance (cleanup + assessment)'; Risk='LOW'; Stages=@('Preflight','Audit','Cleanup','WindowsUpdate','Applications','Verification','FinalReport') }
        @{ Label='Malware Investigation'; Risk='LOW'; Stages=@('Preflight','Security','EventLogs','Malware','Verification','FinalReport') }
        @{ Label='Network Troubleshooting'; Risk='LOW'; Stages=@('Preflight','Network','Verification','FinalReport') }
        @{ Label='Windows Repair (DISM/SFC/CBS)'; Risk='MODERATE'; Stages=@('Preflight','Backup','Repair','Verification','FinalReport') }
    )
    foreach ($wf in $workflows) {
        $panel = New-Object System.Windows.Controls.StackPanel
        $panel.Orientation = 'Horizontal'; $panel.Margin = '0,4'
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = $wf.Label; $btn.Width = 300; $btn.Padding = '8'; $btn.HorizontalContentAlignment = 'Left'
        $riskColor = switch ($wf.Risk) { 'SAFE' {'#FF66BB6A'} 'LOW' {'#FFAED581'} 'MODERATE' {'#FFFFB74D'} 'HIGH' {'#FFEF5350'} default {'#FFEF5350'} }
        $riskLabel = New-Object System.Windows.Controls.TextBlock
        $riskLabel.Text = $wf.Risk; $riskLabel.Foreground = $riskColor; $riskLabel.VerticalAlignment = 'Center'; $riskLabel.Margin = '10,0,0,0'
        $stagesCopy = $wf.Stages
        $labelCopy = $wf.Label
        $btn.Add_Click({ Start-GuiWorkflow -ExtraArgs (@('-Stage') + $stagesCopy) -Label $labelCopy }.GetNewClosure())
        [void]$panel.Children.Add($btn); [void]$panel.Children.Add($riskLabel)
        [void]$workflowPanel.Children.Add($panel)
        $allButtons.Add($btn)
    }
    $customPanel = New-Object System.Windows.Controls.StackPanel
    $customPanel.Orientation = 'Horizontal'; $customPanel.Margin = '0,14,0,0'
    $customLabel = New-Object System.Windows.Controls.TextBlock
    $customLabel.Text = 'Custom stages (comma-separated):'; $customLabel.Foreground = 'White'; $customLabel.VerticalAlignment = 'Center'; $customLabel.Margin='0,0,8,0'
    $customBox = New-Object System.Windows.Controls.TextBox
    $customBox.Width = 300
    $customBtn = New-Object System.Windows.Controls.Button
    $customBtn.Content = 'Run'; $customBtn.Padding = '10,4'; $customBtn.Margin = '8,0,0,0'
    $customBtn.Add_Click({
        $names = @($customBox.Text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($names.Count -gt 0) { Start-GuiWorkflow -ExtraArgs (@('-Stage') + $names) -Label ('Custom: ' + ($names -join ',')) }
    }.GetNewClosure())
    [void]$customPanel.Children.Add($customLabel); [void]$customPanel.Children.Add($customBox); [void]$customPanel.Children.Add($customBtn)
    [void]$workflowPanel.Children.Add($customPanel)
    $allButtons.Add($customBtn)

    # ---- Windows Tweaks page ----
    $tweaksList = $window.FindName('TweaksList')
    function Update-TweaksList {
        $tweaksList.Items.Clear()
        foreach ($t in (Get-TweakCatalog)) {
            $state = & $t.Get
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = ('{0}   [Current: {1}]   Risk: {2}' -f $t.Name, $state.Current, $state.Risk)
            $cb.Tag = $t.Id
            $cb.Margin = '4'
            [void]$tweaksList.Items.Add($cb)
        }
    }
    $window.FindName('BtnRefreshTweaks').Add_Click({ Update-TweaksList })
    $window.FindName('BtnApplyTweaks').Add_Click({
        $ids = @($tweaksList.Items | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
        if ($ids.Count -gt 0) { Start-GuiWorkflow -ExtraArgs (@('-ApplyTweaks') + $ids) -Label 'Apply tweaks' }
    })
    $window.FindName('BtnRestoreTweaks').Add_Click({
        $ids = @($tweaksList.Items | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
        if ($ids.Count -gt 0) { Start-GuiWorkflow -ExtraArgs (@('-RestoreTweaks') + $ids) -Label 'Restore tweaks' }
    })
    $allButtons.Add($window.FindName('BtnRefreshTweaks'))
    $allButtons.Add($window.FindName('BtnApplyTweaks'))
    $allButtons.Add($window.FindName('BtnRestoreTweaks'))

    # ---- Application Catalog page ----
    $appsList = $window.FindName('AppsList')
    foreach ($id in ($script:AppCatalog.Keys | Sort-Object)) {
        $app = $script:AppCatalog[$id]
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = ('[{0}] {1}' -f $app.category, $app.content)
        $cb.Tag = $id
        $cb.Margin = '4'
        [void]$appsList.Items.Add($cb)
    }
    $window.FindName('BtnInstallApps').Add_Click({
        $ids = @($appsList.Items | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
        if ($ids.Count -gt 0) { Start-GuiWorkflow -ExtraArgs (@('-InstallApps') + $ids) -Label 'Install applications' }
    })
    $allButtons.Add($window.FindName('BtnInstallApps'))

    # ---- Technician Tools page ----
    $toolsPanel = $window.FindName('ToolsPanel')
    foreach ($tool in (Get-TechnicianToolsList)) {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = $tool.N; $btn.Width = 200; $btn.Height = 40; $btn.Margin = '4'
        $toolCopy = $tool
        $btn.Add_Click({
            try {
                if ($toolCopy.A) { Start-Process -FilePath $toolCopy.P -ArgumentList $toolCopy.A }
                else { Start-Process -FilePath $toolCopy.P }
            } catch { $statusText.Text = 'Could not launch ' + $toolCopy.N + ': ' + $_.Exception.Message }
        }.GetNewClosure())
        [void]$toolsPanel.Children.Add($btn)
        $allButtons.Add($btn)
    }

    # ---- Reports page ----
    $reportsList = $window.FindName('ReportsList')
    function Update-ReportsList {
        $reportsList.Items.Clear()
        if (Test-Path -LiteralPath $script:Paths.Reports) {
            Get-ChildItem -Path $script:Paths.Reports -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending |
                ForEach-Object {
                    $item = New-Object System.Windows.Controls.ListBoxItem
                    $item.Content = $_.Name + '   (' + $_.LastWriteTime + ')'
                    $item.Tag = $_.FullName
                    [void]$reportsList.Items.Add($item)
                }
        }
    }
    $window.FindName('BtnOpenReport').Add_Click({
        if ($reportsList.SelectedItem) { Invoke-Item -LiteralPath $reportsList.SelectedItem.Tag }
    })
    $window.FindName('BtnOpenReportsFolder').Add_Click({ Invoke-Item -LiteralPath $script:Paths.Reports })
    $allButtons.Add($window.FindName('BtnOpenReport'))
    $allButtons.Add($window.FindName('BtnOpenReportsFolder'))
    Update-ReportsList

    # ---- Settings page ----
    $txtCompanyName = $window.FindName('TxtCompanyName'); $txtCompanyTagline = $window.FindName('TxtCompanyTagline')
    $txtLogoPath = $window.FindName('TxtLogoPath'); $txtSDIOPath = $window.FindName('TxtSDIOPath'); $txtWSUSPath = $window.FindName('TxtWSUSPath')
    $chkDriverInstall = $window.FindName('ChkAllowDriverInstall'); $chkWinUpdateRepair = $window.FindName('ChkAllowWindowsUpdateRepair')
    $chkDebloat = $window.FindName('ChkAllowDebloatChanges'); $chkNetworkReset = $window.FindName('ChkAllowNetworkReset')
    $chkReboot = $window.FindName('ChkAllowReboot')

    $txtCompanyName.Text = [string]$script:Config.CompanyName
    $txtCompanyTagline.Text = [string]$script:Config.CompanyTagline
    $txtLogoPath.Text = [string]$script:Config.LogoPath
    $txtSDIOPath.Text = [string]$script:Config.SDIOPath
    $txtWSUSPath.Text = [string]$script:Config.WSUSOfflinePath
    $chkDriverInstall.IsChecked = [bool]$script:Config.Safety.AllowDriverInstall
    $chkWinUpdateRepair.IsChecked = [bool]$script:Config.Safety.AllowWindowsUpdateRepair
    $chkDebloat.IsChecked = [bool]$script:Config.Safety.AllowDebloatChanges
    $chkNetworkReset.IsChecked = [bool]$script:Config.Safety.AllowNetworkReset
    $chkReboot.IsChecked = [bool]$script:Config.Safety.AllowReboot

    $window.FindName('BtnSaveSettings').Add_Click({
        $script:Config.CompanyName = $txtCompanyName.Text
        $script:Config.CompanyTagline = $txtCompanyTagline.Text
        $script:Config.LogoPath = $txtLogoPath.Text
        $script:Config.SDIOPath = $txtSDIOPath.Text
        $script:Config.WSUSOfflinePath = $txtWSUSPath.Text
        $script:Config.Safety.AllowDriverInstall = [bool]$chkDriverInstall.IsChecked
        $script:Config.Safety.AllowWindowsUpdateRepair = [bool]$chkWinUpdateRepair.IsChecked
        $script:Config.Safety.AllowDebloatChanges = [bool]$chkDebloat.IsChecked
        $script:Config.Safety.AllowNetworkReset = [bool]$chkNetworkReset.IsChecked
        $script:Config.Safety.AllowReboot = [bool]$chkReboot.IsChecked
        try {
            $cfgPath = if ($ConfigPath) { $ConfigPath } else { Join-Path $script:Paths.Config 'Toolkit.json' }
            Write-AtomicText -Path $cfgPath -Content (ConvertTo-JsonSafe $script:Config)
            $statusText.Text = 'Settings saved to ' + $cfgPath
        } catch {
            $statusText.Text = 'Could not save settings: ' + $_.Exception.Message
        }
    })
    $allButtons.Add($window.FindName('BtnSaveSettings'))

    Update-TweaksList
    [void]$window.ShowDialog()
}
#endregion

function ConvertTo-ElevationArguments {
    # Generic forwarding via $PSBoundParameters, as required: adding a new parameter to
    # this script (like -Gui) never requires touching this function again.
    $argsOut = New-Object System.Collections.ArrayList
    [void]$argsOut.Add('-NoProfile')
    [void]$argsOut.Add('-ExecutionPolicy')
    [void]$argsOut.Add('Bypass')
    [void]$argsOut.Add('-File')
    [void]$argsOut.Add($PSCommandPath)

    foreach ($key in $script:AllBoundParameters.Keys) {
        $value = $script:AllBoundParameters[$key]
        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) { [void]$argsOut.Add('-' + $key) }
        } elseif ($value -is [array]) {
            if ($value.Count -gt 0) {
                [void]$argsOut.Add('-' + $key)
                foreach ($item in $value) { [void]$argsOut.Add([string]$item) }
            }
        } elseif ($null -ne $value -and [string]$value -ne '') {
            [void]$argsOut.Add('-' + $key)
            [void]$argsOut.Add([string]$value)
        }
    }
    return $argsOut.ToArray()
}

function Start-Elevated {
    $ps = (Get-Command powershell.exe -ErrorAction SilentlyContinue)
    if (-not $ps) { throw 'Windows PowerShell executable was not found.' }
    $argList = ConvertTo-ElevationArguments
    try {
        Start-Process -FilePath $ps.Source -ArgumentList $argList -Verb RunAs -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Host ('Elevation was cancelled or failed: ' + $_.Exception.Message) -ForegroundColor Red
        return $false
    }
}

function Invoke-SelectedStages {
    param([string[]]$Requested)

    $order = Get-StageOrder
    if ($Requested -contains 'All') {
        $selected = $order
    } else {
        $selected = @()
        foreach ($name in $order) {
            if ($Requested -contains $name) { $selected += $name }
        }
        $unknown = @($Requested | Where-Object {$order -notcontains $_})
        foreach ($u in $unknown) {
            Write-Log ('Unknown stage: ' + $u) 'Warning'
            Add-Finding -Category 'Input' -Severity 'Low' `
                -Description ('Unknown stage selector: ' + $u) `
                -RecommendedAction 'Use -Help to review supported stages.' -Confidence 'High'
        }
    }

    $script:State.PendingStages = @($selected)
    Write-State

    foreach ($name in $selected) {
        if ($script:State.CompletedStages -contains $name -and $name -notin @('Verification','Finalize','FinalReport')) {
            continue
        }
        $action = Get-StageAction $name
        if ($action) {
            Invoke-Stage -Name $name -Action $action
        }
        $script:State.PendingStages = @($selected | Where-Object {$script:State.CompletedStages -notcontains $_})
        Write-State
    }
}

function Main {
    Initialize-Paths
    Initialize-Config
    Initialize-AppCatalog
    Initialize-Logging

    $script:Toolkit.IsElevated = Test-IsAdministrator

    if ($Help) {
        Show-Help
        return
    }

    if (-not $script:Toolkit.IsElevated) {
        Write-Log 'Administrator privileges are required. Requesting elevation...' 'Warning'
        if (Start-Elevated) { return }
        throw 'Toolkit cannot continue without Administrator privileges.'
    }

    Initialize-State
    Show-Banner

    if ($InstallApps -or $ApplyTweaks -or $RestoreTweaks) {
        if ($InstallApps) {
            foreach ($id in $InstallApps) {
                $app = $script:AppCatalog[$id]
                if (-not $app) { Write-Log ('Unknown application catalog id: ' + $id) 'Warning'; continue }
                if ($WhatIf) {
                    Add-Result (New-Result 'Applications' ('Install ' + $app.content) 'Skipped' -Skipped:$true `
                        -Message ('WhatIf: would run winget install --id ' + $app.winget))
                    continue
                }
                Write-Log ('Installing ' + $app.content + ' via winget...')
                $r = Invoke-ExternalProcess -FilePath 'winget.exe' `
                    -ArgumentList @('install','--id',$app.winget,'-e','--silent','--accept-package-agreements','--accept-source-agreements') `
                    -TimeoutSeconds 600
                $r.Stage = 'Applications'; $r.Task = 'Install ' + $app.content; $r.Tool = $app.winget
                [void]$script:Results.Add($r)
                Add-Change -Action 'Install application' -Target $app.content -Result $r.Status `
                    -Changed:($r.Status -eq 'Succeeded') -RiskLevel 'LOW'
            }
        }
        Invoke-WindowsTweaksHeadless
        Invoke-Stage -Name 'FinalReport' -Action { Invoke-FinalReport }
        $script:State.EndUtc = Get-UtcString
        $script:State.Status = 'Completed'
        Write-State
        return
    }

    if ($Gui) {
        Show-MainGui
        return
    }

    $selected = $Stage
    if ($selected.Count -eq 0) {
        if ($Unattended) {
            $selected = @('Preflight','Audit','Hardware','Storage','Security','EventLogs','Performance','Network','Drivers','WindowsUpdate','Verification','Finalize','FinalReport')
        } else {
            $selected = Show-InteractiveMenu
            if ($selected.Count -eq 0) { return }
        }
    }

    Invoke-SelectedStages -Requested $selected

    if ($selected -notcontains 'FinalReport') {
        Invoke-Stage -Name 'FinalReport' -Action { Invoke-FinalReport }
    }

    $script:State.EndUtc = Get-UtcString
    $script:State.Status = 'Completed'
    $script:State.RebootRequired = $script:RebootRequired
    Write-State

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host (' RUN COMPLETE: ' + $script:OverallStatus) -ForegroundColor Cyan
    Write-Host (' Findings: ' + $script:Findings.Count) -ForegroundColor White
    Write-Host (' Results:  ' + $script:Results.Count) -ForegroundColor White
    Write-Host (' Reboot:   ' + $script:RebootRequired) -ForegroundColor White
    Write-Host (' Reports:  ' + $script:Paths.Reports) -ForegroundColor White
    Write-Host '============================================================' -ForegroundColor Cyan

    if (-not $Unattended) {
        Read-Host 'Press ENTER to exit' | Out-Null
    }
}

try {
    Main
} catch {
    try {
        Write-Log ('Fatal error: ' + $_.Exception.Message) 'Error'
    } catch {
        Write-Host ('Fatal error: ' + $_.Exception.Message) -ForegroundColor Red
    }
    exit 1
} finally {
    if ($script:TranscriptWriter) {
        try { $script:TranscriptWriter.Flush(); $script:TranscriptWriter.Dispose() } catch {}
    }
}
