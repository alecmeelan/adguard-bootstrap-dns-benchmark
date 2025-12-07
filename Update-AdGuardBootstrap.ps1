<#
.SYNOPSIS
  Benchmarks public DNS resolvers and updates AdGuard Home bootstrap DNS
  with the fastest IPv4 servers.

.DESCRIPTION
  - Runs a "real world" style DNS latency test for each resolver.
  - Picks the fastest N resolvers with zero failures.
  - Updates AdGuard Home's dns.bootstrap_dns via /control/dns_config.
  - Intended to be run periodically (e.g. daily via Task Scheduler).

  NOTE: For unattended use, consider storing credentials securely instead of
        hardcoding them. This script uses simple Basic Auth for clarity.
#>

param(
    [int]$TotalQueriesPerServer = 80,
    [int]$PerQueryTimeoutMs     = 2000,
    [int]$TopNBootstrap         = 4,

    # AdGuard Home API endpoint (change port/host if needed)
    [string]$AdGuardBaseUrl     = "http://127.0.0.1:8080",

    # AdGuard Home admin credentials (same as Web UI)
    [string]$AdGuardUser        = "admin",
    [string]$AdGuardPassword    = "changeme",

    # Optional: log file for daily runs
    [string]$LogFilePath        = "$PSScriptRoot\AdGuardBootstrapBenchmark.log"
)

# -------------------- Resolver list --------------------
# These are the IPs we’ll benchmark and potentially use as bootstrap_dns.
$resolvers = @(
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

# Domains used to simulate more realistic mixed traffic
$TestDomains = @(
    "example.com",
    "microsoft.com",
    "google.com",
    "cloudflare.com",
    "github.com",
    "reddit.com",
    "wikipedia.org",
    "nytimes.com",
    "spotify.com",
    "twitch.tv"
)

# -------------------- Helper: logging --------------------
function Write-Log {
    param(
        [string]$Message
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$timestamp] $Message"
    Write-Host $line
    if ($LogFilePath) {
        Add-Content -Path $LogFilePath -Value $line
    }
}

# -------------------- Helper: HTTP auth header --------------------
function Get-AdGuardAuthHeader {
    param(
        [string]$User,
        [string]$Password
    )
    $pair  = "$User`:$Password"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $b64   = [Convert]::ToBase64String($bytes)
    return @{ Authorization = "Basic $b64" }
}

# -------------------- Benchmark function --------------------
function Test-DnsResolvers {
    param(
        [array]$Resolvers,
        [array]$Domains,
        [int]$TotalQueriesPerServer,
        [int]$TimeoutMs
    )

    $results = @()

    foreach ($resolver in $Resolvers) {
        $name = $resolver.Name
        $ip   = $resolver.IP

        Write-Log "Testing $name ($ip)..."

        $successCount = 0
        $failCount    = 0
        $latencies    = New-Object System.Collections.Generic.List[double]

        for ($i = 1; $i -le $TotalQueriesPerServer; $i++) {
            $domain = $Domains[ (Get-Random -Minimum 0 -Maximum $Domains.Count) ]

            try {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()

                $job = Start-Job -ScriptBlock {
                    param($d, $server)
                    Resolve-DnsName -Name $d -Server $server -Type A -ErrorAction Stop
                } -ArgumentList $domain, $ip

                if (Wait-Job -Job $job -Timeout ($TimeoutMs / 1000.0)) {
                    $jobResult = Receive-Job -Job $job -ErrorAction SilentlyContinue
                    $sw.Stop()
                    if ($jobResult) {
                        $successCount++
                        $latencies.Add($sw.Elapsed.TotalMilliseconds) | Out-Null
                    } else {
                        $failCount++
                    }
                } else {
                    # timeout
                    $failCount++
                    Write-Log "  [$name] Query $i for $domain timed out (> $TimeoutMs ms)"
                }
            } catch {
                $failCount++
                Write-Log "  [$name] Query $i for $domain threw error: $($_.Exception.Message)"
            } finally {
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
        }

        if ($latencies.Count -gt 0) {
            $avg = [Math]::Round(($latencies | Measure-Object -Average).Average, 2)
            $min = [Math]::Round(($latencies | Measure-Object -Minimum).Minimum, 2)
            $max = [Math]::Round(($latencies | Measure-Object -Maximum).Maximum, 2)
        } else {
            $avg = $null
            $min = $null
            $max = $null
        }

        $result = [PSCustomObject]@{
            Name      = $name
            IP        = $ip
            Queries   = $TotalQueriesPerServer
            Successes = $successCount
            Failures  = $failCount
            AvgMs     = $avg
            MinMs     = $min
            MaxMs     = $max
        }

        $results += $result

        Write-Log ("Finished {0} ({1}) -> Success: {2}, Fail: {3}, Avg: {4} ms" -f `
            $name, $ip, $successCount, $failCount, ($avg -as [string]))
    }

    return $results
}

# -------------------- AdGuard Home config helpers --------------------

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
    Invoke-RestMethod -Uri $url -Headers $Headers -Method Post -ContentType "application/json" -Body $json | Out-Null
}

# -------------------- Main --------------------

Write-Log "===== Starting AdGuard Home bootstrap DNS benchmark ====="
Write-Log "Queries per resolver: $TotalQueriesPerServer, timeout: $PerQueryTimeoutMs ms"

# 1) Run the benchmark
$benchmarkResults = Test-DnsResolvers -Resolvers $resolvers `
                                      -Domains $TestDomains `
                                      -TotalQueriesPerServer $TotalQueriesPerServer `
                                      -TimeoutMs $PerQueryTimeoutMs

Write-Host ""
Write-Host "Summary (real-world style latency):" -ForegroundColor Cyan
$benchmarkResults |
    Sort-Object AvgMs |
    Format-Table Name, IP, Queries, Successes, Failures, AvgMs, MinMs, MaxMs -AutoSize

# 2) Pick fastest N with zero failures and non-null AvgMs
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

# 3) Build auth header for AdGuard Home
$headers = Get-AdGuardAuthHeader -User $AdGuardUser -Password $AdGuardPassword

# 4) Get current DNS config, update bootstrap_dns, and push back
try {
    $dnsConfig = Get-AdGuardDnsConfig -BaseUrl $AdGuardBaseUrl -Headers $headers

    # dnsConfig is essentially DNSConfig; bootstrap_dns is an array of strings.
    # We replace it with the selected IPs.
    $newBootstrap = $selected.IP
    Write-Log "Updating dns.bootstrap_dns to: $($newBootstrap -join ', ')"

    $dnsConfig.bootstrap_dns = $newBootstrap

    Set-AdGuardDnsConfig -BaseUrl $AdGuardBaseUrl -Headers $headers -Config $dnsConfig

    Write-Log "AdGuard Home bootstrap DNS successfully updated."
} catch {
    Write-Log "Failed to update AdGuard Home: $($_.Exception.Message)"
    exit 1
}

Write-Log "===== Finished AdGuard Home bootstrap DNS benchmark ====="
