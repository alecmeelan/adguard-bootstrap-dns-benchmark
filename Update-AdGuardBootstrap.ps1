<#
.SYNOPSIS
    Benchmark public DNS resolvers and update AdGuard Home bootstrap DNS
    with the fastest, most reliable servers.

.DESCRIPTION
    - Runs a "real-world" style DNS latency test against a list of
      public resolvers (A or optionally mixed A/AAAA queries).
    - Measures average/min/max latency and failures per resolver.
    - Selects the fastest N resolvers with zero failures.
    - Updates AdGuard Home's dns.bootstrap_dns via its HTTP API
      using HTTP Basic authentication.

.PARAMETER Iterations
    Number of DNS queries per resolver.

.PARAMETER TopNBootstrap
    Number of top resolvers to write into bootstrap_dns.

.PARAMETER MixAAAA
    If set, randomly mix A and AAAA queries instead of A only.

.PARAMETER DryRun
    If set, do not modify AdGuard Home. Only run tests and show what would be applied.

.PARAMETER AdGuardBaseUrl
    Base URL for AdGuard Home Web UI / API (for example http://127.0.0.1:8080).

.PARAMETER AdGuardUser
    AdGuard Home username.

.PARAMETER AdGuardPassword
    AdGuard Home password.

.PARAMETER LogFilePath
    Optional log file path for logging. If omitted, logs only to console.
#>

[CmdletBinding()]
param(
    [int]$Iterations        = 40,
    [int]$TopNBootstrap     = 4,

    # Configure these three for your environment before running or publishing.
    [string]$AdGuardBaseUrl = "http://127.0.0.1:8080",
    [string]$AdGuardUser    = "Username",
    [string]$AdGuardPassword = "Password",

    [switch]$MixAAAA,
    [switch]$DryRun,

    [string]$LogFilePath    = "$PSScriptRoot\AdGuardBootstrapBenchmark.log"
)

# ---------- Resolver list (IPv4 only) ----------
$Resolvers = @(
    @{ Name = "Cloudflare-1"       ; IP = "1.1.1.1"           }
    @{ Name = "Cloudflare-2"       ; IP = "1.0.0.1"           }
    @{ Name = "Google-1"           ; IP = "8.8.8.8"           }
    @{ Name = "Google-2"           ; IP = "8.8.4.4"           }
    @{ Name = "Quad9-1"            ; IP = "9.9.9.9"           }
    @{ Name = "Quad9-2"            ; IP = "149.112.112.112"   }
    @{ Name = "OpenDNS-1"          ; IP = "208.67.222.222"    }
    @{ Name = "OpenDNS-2"          ; IP = "208.67.220.220"    }
    @{ Name = "CleanBrowsingSec-1" ; IP = "185.228.168.9"     }
    @{ Name = "CleanBrowsingSec-2" ; IP = "185.228.169.9"     }
    @{ Name = "ControlD-p0-1"      ; IP = "76.76.2.0"         }
    @{ Name = "ControlD-p0-2"      ; IP = "76.76.10.0"        }
    @{ Name = "AdGuard-1"          ; IP = "94.140.14.14"      }
    @{ Name = "AdGuard-2"          ; IP = "94.140.15.15"      }
    @{ Name = "RabbitSec-1"        ; IP = "149.112.121.20"    }
    @{ Name = "RabbitSec-2"        ; IP = "149.112.122.20"    }
    @{ Name = "Surfshark-1"        ; IP = "194.169.169.169"   }
    @{ Name = "v.recipes-1"        ; IP = "64.6.64.6"         }
    @{ Name = "v.recipes-2"        ; IP = "64.6.65.6"         }
)

# Domains to simulate realistic traffic
$TestDomains = @(
    "example.com",
    "google.com",
    "cloudflare.com",
    "microsoft.com",
    "github.com",
    "reddit.com",
    "wikipedia.org",
    "nytimes.com",
    "spotify.com",
    "twitch.tv"
)

# ---------- Logging helper ----------
function Write-Log {
    param([string]$Message)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$timestamp] $Message"
    Write-Host $line
    if ($LogFilePath) {
        Add-Content -Path $LogFilePath -Value $line
    }
}

# ---------- Build Basic Auth headers ----------
function New-AdGuardHeaders {
    param(
        [string]$UserName,
        [string]$Password
    )
    $pair   = "$UserName`:$Password"
    $bytes  = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [Convert]::ToBase64String($bytes)
    return @{ Authorization = "Basic $base64" }
}

# ---------- DNS benchmark (real-world style, no jobs) ----------
function Test-DnsResolvers {
    param(
        [array]$Resolvers,
        [array]$Domains,
        [int]$Iterations,
        [switch]$MixAAAA,
        [int]$MaxConsecutiveFailures = 5
    )

    $results = @()
    $total = $Resolvers.Count
    $idx = 0

    foreach ($resolver in $Resolvers) {
        $idx++
        $name = $resolver.Name
        $ip   = $resolver.IP

        Write-Progress -Id 1 -Activity "Testing DNS resolvers" `
            -Status "Server $idx of $($total): $name ($ip)" `
            -PercentComplete ([int](($idx - 1) / $total * 100))

        Write-Log "Testing $name ($ip)..."

        $latencies = @()
        $success   = 0
        $fail      = 0
        $consecutiveFailures = 0

        for ($i = 1; $i -le $Iterations; $i++) {

            if ($consecutiveFailures -ge $MaxConsecutiveFailures) {
                Write-Log "  Too many consecutive failures for $name, skipping remaining queries."
                break
            }

            $domain = $Domains | Get-Random

            if ($MixAAAA) {
                $recordType = @("A","AAAA") | Get-Random
            } else {
                $recordType = "A"
            }

            Write-Progress -Id 2 -ParentId 1 -Activity "Testing $name" `
                -Status "Query $i of $Iterations ($recordType $domain)" `
                -PercentComplete ([int]($i / $Iterations * 100))

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $null = Resolve-DnsName -Name $domain -Server $ip -Type $recordType -ErrorAction Stop
                $sw.Stop()
                $latencies += $sw.Elapsed.TotalMilliseconds
                $success++
                $consecutiveFailures = 0
            }
            catch {
                $sw.Stop()
                $fail++
                $consecutiveFailures++
                Write-Log "  [$name] Query $i for $domain ($recordType) failed: $($_.Exception.Message)"
            }

            Start-Sleep -Milliseconds (Get-Random -Min 50 -Max 200)
        }

        if ($latencies.Count -gt 0) {
            $avg = [Math]::Round(($latencies | Measure-Object -Average).Average, 2)
            $min = [Math]::Round(($latencies | Measure-Object -Minimum).Minimum, 2)
            $max = [Math]::Round(($latencies | Measure-Object -Maximum).Maximum, 2)
        } else {
            $avg = $min = $max = $null
        }

        $obj = [PSCustomObject]@{
            Name      = $name
            IP        = $ip
            Queries   = $Iterations
            Successes = $success
            Failures  = $fail
            AvgMs     = $avg
            MinMs     = $min
            MaxMs     = $max
        }

        $results += $obj
        Write-Log ("Finished {0} ({1}) -> Success: {2}, Fail: {3}, Avg: {4} ms" -f `
            $name, $ip, $success, $fail, ($avg -as [string]))
    }

    Write-Progress -Id 1 -Completed $true
    Write-Progress -Id 2 -Completed $true
    return $results
}

# ---------- AdGuard API helpers ----------
function Get-AdGuardDnsConfig {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers
    )
    $url = "$BaseUrl/control/dns_info"
    Write-Log "Fetching current AdGuard Home DNS config from $url..."
    return Invoke-RestMethod -Uri $url -Headers $Headers -Method Get
}

function Set-AdGuardDnsConfig {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers,
        [object]$Config
    )
    $url = "$BaseUrl/control/dns_config"
    Write-Log "Updating AdGuard Home DNS config at $url..."
    $json = $Config | ConvertTo-Json -Depth 10

    Invoke-RestMethod `
        -Uri $url `
        -Headers $Headers `
        -Method Post `
        -ContentType "application/json" `
        -Body $json | Out-Null
}

# ---------- Main ----------

Write-Log "===== Starting AdGuard Home bootstrap DNS benchmark ====="
Write-Log "Queries per resolver: $Iterations"

# Check for Resolve-DnsName availability
if (-not (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)) {
    Write-Log "ERROR: Resolve-DnsName cmdlet is not available. This script requires Windows DNSClient tools."
    exit 1
}

if (-not $AdGuardUser -or -not $AdGuardPassword -or $AdGuardPassword -eq "CHANGE_ME_PASSWORD") {
    Write-Log "ERROR: Configure AdGuardBaseUrl, AdGuardUser, and AdGuardPassword at the top of the script."
    exit 1
}

$headers = New-AdGuardHeaders -UserName $AdGuardUser -Password $AdGuardPassword

# 1) Benchmark resolvers
$benchmarkResults = Test-DnsResolvers -Resolvers $Resolvers -Domains $TestDomains -Iterations $Iterations -MixAAAA:$MixAAAA

Write-Host ""
Write-Host "Summary (real-world style latency):" -ForegroundColor Cyan
$benchmarkResults |
    Sort-Object AvgMs |
    Format-Table Name, IP, Queries, Successes, Failures, AvgMs, MinMs, MaxMs -AutoSize

# 2) Filter and pick top N
$eligible = $benchmarkResults |
    Where-Object { $_.Failures -eq 0 -and $_.AvgMs -ne $null } |
    Sort-Object AvgMs

if ($eligible.Count -lt 1) {
    Write-Log "No eligible resolvers with successful queries. Aborting update."
    exit 1
}

$selected = $eligible | Select-Object -First $TopNBootstrap

Write-Host ""
Write-Host "Selected bootstrap DNS servers:" -ForegroundColor Green
$selected | Format-Table Name, IP, AvgMs, MinMs, MaxMs -AutoSize

if ($DryRun) {
    Write-Log "Dry run is enabled. Not updating AdGuard Home. This is what would be applied: $($selected.IP -join ', ')"
    Write-Log "===== Finished AdGuard Home bootstrap DNS benchmark (DRY RUN) ====="
    exit 0
}

# 3) Apply to AdGuard
try {
    $dnsConfig = Get-AdGuardDnsConfig -BaseUrl $AdGuardBaseUrl -Headers $headers

    $newBootstrap = $selected.IP
    Write-Log "Updating dns.bootstrap_dns to: $($newBootstrap -join ', ')"

    $dnsConfig.bootstrap_dns = $newBootstrap
    Set-AdGuardDnsConfig -BaseUrl $AdGuardBaseUrl -Headers $headers -Config $dnsConfig

    Write-Log "AdGuard Home bootstrap DNS successfully updated."
}
catch {
    $statusCode = $null
    if ($_.Exception.Response) {
        try {
            $statusCode = $_.Exception.Response.StatusCode.value__
        } catch {}
    }
    if ($statusCode) {
        Write-Log "Failed to update AdGuard Home (HTTP $statusCode): $($_.Exception.Message)"
    } else {
        Write-Log "Failed to update AdGuard Home: $($_.Exception.Message)"
    }
    exit 1
}

Write-Log "===== Finished AdGuard Home bootstrap DNS benchmark ====="
