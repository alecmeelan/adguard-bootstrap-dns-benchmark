<#
.SYNOPSIS
    Benchmark multiple public DNS resolvers and update AdGuard Home
    bootstrap DNS with the fastest, most reliable servers.

.DESCRIPTION
    - Runs a "real-world" style DNS latency test against a list of
      public resolvers.
    - Measures average/min/max latency and failures per resolver.
    - Selects the fastest N resolvers with zero failures.
    - Updates AdGuard Home's dns.bootstrap_dns via its HTTP API.

    Intended to be run periodically (e.g., via Task Scheduler).

.PARAMETER Iterations
    Number of DNS queries per resolver.

.PARAMETER TopNBootstrap
    Number of top resolvers to write into bootstrap_dns.

.PARAMETER AdGuardBaseUrl
    Base URL for AdGuard Home Web UI / API (e.g. http://127.0.0.1:3000).

.PARAMETER AdGuardUser
    AdGuard Home username. If not set, taken from $env:ADGUARD_USER.

.PARAMETER AdGuardPassword
    AdGuard Home password. If not set, taken from $env:ADGUARD_PASS.

.PARAMETER LogFilePath
    Optional log file path. If omitted, logs only to console.

.EXAMPLE
    .\Update-AdGuardBootstrap.ps1

.EXAMPLE
    $env:ADGUARD_USER = "admin"
    $env:ADGUARD_PASS = "supersecret"
    .\Update-AdGuardBootstrap.ps1 -AdGuardBaseUrl "http://127.0.0.1:8080" -TopNBootstrap 4
#>

[CmdletBinding()]
param(
    [int]$Iterations        = 40,
    [int]$TopNBootstrap     = 4,
    [string]$AdGuardBaseUrl = "http://127.0.0.1:3000",
    [string]$AdGuardUser    = $env:ADGUARD_USER,
    [string]$AdGuardPassword = $env:ADGUARD_PASS,
    [string]$LogFilePath
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

# ---------- DNS benchmark (real-world style, no jobs) ----------
function Test-DnsResolvers {
    param(
        [array]$Resolvers,
        [array]$Domains,
        [int]$Iterations,
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
            -Status "Server $idx of $total: $name ($ip)" `
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
            $recordType = "A"  # keep simple and comparable

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
                Write-Log "  [$name] Query $i for $domain failed: $($_.Exception.Message)"
            }

            # Small jitter to simulate real usage
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
        [pscredential]$Credential
    )
    $url = "$BaseUrl/control/dns_info"
    Write-Log "Fetching current AdGuard Home DNS config from $url..."
    return Invoke-RestMethod -Uri $url -Credential $Credential -Method Get
}

function Set-AdGuardDnsConfig {
    param(
        [string]$BaseUrl,
        [pscredential]$Credential,
        [object]$Config
    )
    $url = "$BaseUrl/control/dns_config"
    Write-Log "Updating AdGuard Home DNS config at $url..."
    $json = $Config | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $url -Credential $Credential -Method Post `
        -ContentType "application/json" -Body $json | Out-Null
}

# ---------- Main ----------
Write-Log "===== Starting AdGuard Home bootstrap DNS benchmark ====="
Write-Log "Queries per resolver: $Iterations"

if (-not $AdGuardUser -or -not $AdGuardPassword) {
    Write-Log "ERROR: AdGuard credentials not provided. Set AdGuardUser/AdGuardPassword or ADGUARD_USER/ADGUARD_PASS."
    exit 1
}

$sec  = ConvertTo-SecureString $AdGuardPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($AdGuardUser, $sec)

# 1) Benchmark
$benchmarkResults = Test-DnsResolvers -Resolvers $Resolvers -Domains $TestDomains -Iterations $Iterations

Write-Host ""
Write-Host "Summary (real-world style latency):" -ForegroundColor Cyan
$benchmarkResults |
    Sort-Object AvgMs |
    Format-Table Name, IP, Queries, Successes, Failures, AvgMs, MinMs, MaxMs -AutoSize

# 2) Filter & pick top N
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

# 3) Apply to AdGuard
try {
    $dnsConfig = Get-AdGuardDnsConfig -BaseUrl $AdGuardBaseUrl -Credential $cred

    $newBootstrap = $selected.IP
    Write-Log "Updating dns.bootstrap_dns to: $($newBootstrap -join ', ')"

    $dnsConfig.bootstrap_dns = $newBootstrap
    Set-AdGuardDnsConfig -BaseUrl $AdGuardBaseUrl -Credential $cred -Config $dnsConfig

    Write-Log "AdGuard Home bootstrap DNS successfully updated."
}
catch {
    Write-Log "Failed to update AdGuard Home: $($_.Exception.Message)"
    exit 1
}

Write-Log "===== Finished AdGuard Home bootstrap DNS benchmark ====="
