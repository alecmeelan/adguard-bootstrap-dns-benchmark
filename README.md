# AdGuard Home Dynamic Bootstrap DNS Benchmark & Updater

This PowerShell script benchmarks multiple public DNS resolvers using real-world style DNS queries and automatically updates the **Bootstrap DNS** setting in **AdGuard Home** with the fastest, most reliable servers.

This is useful for:
- Improving DoH/DoT startup reliability
- Faster cold-start DNS resolution
- Automatically adapting to changing ISP routing conditions
- Reducing dependence on a single hard-coded bootstrap resolver

---

## Features

- Real-world DNS latency testing (random domains, optional A/AAAA mix)
- Multiple resolver benchmarking
- Automatic selection of top N fastest resolvers
- Direct update of AdGuard Home via its HTTP API
- Daily automation-ready (Windows Task Scheduler)
- Optional logging
- Fully self-contained PowerShell script

---

## Requirements

- Windows with PowerShell 5.1+ or PowerShell 7+
- AdGuard Home with Web/API access enabled
- Network access to public DNS resolvers
- Admin credentials for AdGuard Home

---

## Installation

1. Clone the repository:

```bash
git clone https://github.com/YOUR_USERNAME/adguard-bootstrap-dns-benchmark.git
cd adguard-bootstrap-dns-benchmark
```

---

## Setup

1. Edit the script and update these values:
```bash
[string]$AdGuardBaseUrl  = "http://127.0.0.1:3000"
[string]$AdGuardUser     = "admin"
[string]$AdGuardPassword = "changeme"
```
2. Run the script manually to validate:
```bash
.\Update-AdGuardBootstrap.ps1
```
