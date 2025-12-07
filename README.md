# AdGuard Home Bootstrap DNS Auto-Tuner

This PowerShell script benchmarks public DNS resolvers using **real-world style DNS queries** and automatically updates the **`bootstrap_dns`** setting in **AdGuard Home** with the fastest and most reliable servers.

It is designed for **self-hosted AdGuard Home users** who want:

- Accurate latency measurements (not synthetic ping-style tests)
- Automatic selection of the fastest bootstrap resolvers
- Optional A + AAAA testing for IPv6 realism
- Safe preview mode before making changes
- Fully local execution with no external dependencies

---

## ✅ What This Script Does

1. Tests a curated list of popular public DNS resolvers.
2. Sends repeated real DNS queries (`Resolve-DnsName`) to simulate real traffic.
3. Measures:
   - Average latency  
   - Minimum latency  
   - Maximum latency  
   - Failures
4. Automatically selects the **top N fastest resolvers with zero failures**.
5. Updates:
   - `dns.bootstrap_dns` in AdGuard Home using the official API.
6. Logs all operations to console and file.
7. Supports safe testing via **Dry Run** mode.

---

## ⚠️ Important Safety Notes

- **Never commit your real password to GitHub.**
- The script contains:

    ```powershell
    [string]$AdGuardPassword = "CHANGE_ME_PASSWORD"
    ```

  This is intentional to prevent accidental leaks.

- Always validate output using `-DryRun` before allowing automatic updates.

---

## 🛠 Requirements

- Windows PowerShell 5.1 or newer  
- `Resolve-DnsName` must be available (Windows DNS Client tools)  
- Local or remote AdGuard Home instance  
- AdGuard Home Web API enabled (default)

---

## 🔧 Script Configuration

At the top of the script, configure these values:

```powershell
[string]$AdGuardBaseUrl   = "http://127.0.0.1:8080"
[string]$AdGuardUser      = "Konack"
[string]$AdGuardPassword  = "CHANGE_ME_PASSWORD"
```

Only these lines need editing for most users.

For public repos:

- Leave the default `"CHANGE_ME_PASSWORD"` in the committed script.
- In your local copy, replace it with your real password before running.

---

## ▶️ Usage

### 1. Test safely (no config changes)

```powershell
.\Update-AdGuardBootstrap.ps1 -DryRun
```

This:

- Runs all DNS tests  
- Prints the summary and selected resolvers  
- Does **not** modify AdGuard Home  

---

### 2. Run with real updates

```powershell
.\Update-AdGuardBootstrap.ps1
```

This:

- Benchmarks resolvers  
- Selects the fastest N  
- Updates `dns.bootstrap_dns` via AdGuard Home’s API  

---

### 3. Test mixed A and AAAA records

```powershell
.\Update-AdGuardBootstrap.ps1 -MixAAAA -DryRun
```

This makes the test more realistic for dual-stack environments by mixing IPv4 and IPv6 lookups, without updating your config.

---

### 4. Customize test intensity

```powershell
.\Update-AdGuardBootstrap.ps1 -Iterations 80 -TopNBootstrap 4
```

- `-Iterations 80`: More samples per resolver  
- `-TopNBootstrap 4`: Use the four fastest resolvers for `bootstrap_dns`  

---

## 🎚 Available Parameters

| Parameter          | Type   | Default                 | Description                                                  |
|--------------------|--------|-------------------------|--------------------------------------------------------------|
| `-Iterations`      | int    | `40`                    | DNS queries per resolver                                    |
| `-TopNBootstrap`   | int    | `4`                     | Number of fastest resolvers to apply to `bootstrap_dns`     |
| `-MixAAAA`         | switch | off                     | Randomly mix A and AAAA queries instead of A-only            |
| `-DryRun`          | switch | off                     | Benchmark only, do not update AdGuard Home                  |
| `-AdGuardBaseUrl`  | string | `http://127.0.0.1:8080` | AdGuard Home Web/API base URL                               |
| `-AdGuardUser`     | string | `"Konack"`              | AdGuard Home username                                       |
| `-AdGuardPassword` | string | `"CHANGE_ME_PASSWORD"`  | AdGuard Home password (edit locally, do not commit)         |
| `-LogFilePath`     | string | `.\AdGuardBootstrapBenchmark.log` | Log file path (console logging is always enabled) |

---

## 📄 Sample Output

```text
===== Starting AdGuard Home bootstrap DNS benchmark =====
[2025-12-07 12:00:00] Queries per resolver: 40
[2025-12-07 12:00:01] Testing Cloudflare-1 (1.1.1.1)...
...

Summary (real-world style latency):

Name             IP              Queries Successes Failures AvgMs MinMs MaxMs
----             --              ------- --------- -------- ----- ----- -----
Cloudflare-1     1.1.1.1              40        40        0 12.93 11.74 18.21
Google-1         8.8.8.8              40        40        0 13.41 12.09 21.85
Quad9-1          9.9.9.9              40        40        0 14.19 12.76 26.02
OpenDNS-1        208.67.222.222       40        40        0 15.12 13.43 30.71
...

Selected bootstrap DNS servers:

Name         IP              AvgMs MinMs MaxMs
----         --              ----- ----- -----
Cloudflare-1 1.1.1.1         12.93 11.74 18.21
Google-1     8.8.8.8         13.41 12.09 21.85
Quad9-1      9.9.9.9         14.19 12.76 26.02
OpenDNS-1    208.67.222.222  15.12 13.43 30.71
```

If `-DryRun` is enabled, you’ll also see a log line like:

```text
[2025-12-07 12:00:10] Dry run is enabled. Not updating AdGuard Home. This is what would be applied: 1.1.1.1, 8.8.8.8, 9.9.9.9, 208.67.222.222
```

---

## 🧠 Why This Matters

AdGuard Home uses bootstrap DNS to resolve your encrypted upstreams (DoH/DoT).  
If those bootstrap resolvers are:

- Slow  
- Unreliable  
- Far from your network  

then every secure DNS query can suffer.

This script:

- Keeps your bootstrap layer aligned with what is actually fastest from your location  
- Automatically adapts to routing changes over time  
- Provides a repeatable, scriptable way to validate resolver performance  

---

## 📅 Automation Example (Windows Task Scheduler)

1. Open **Task Scheduler**.
2. Select **Create Task…**

### General

- Run whether user is logged on or not.  
- Run with highest privileges.  

### Triggers

- **New** → **Daily** → choose a time (e.g., 3:00 AM).

### Actions

**Program/script:**

```text
powershell.exe
```

**Arguments:**

```text
-ExecutionPolicy Bypass -File "C:\scripts\Update-AdGuardBootstrap.ps1"
```

Save and enter your credentials.

> Tip: Run with `-DryRun` for a few days first to verify stability, then remove `-DryRun`.

---

## 🔒 Security Considerations

- Do not expose your AdGuard UI/API to the internet without proper protection.
- Store this script in a secure location on your AdGuard host.
- Limit who can read the script file if it contains credentials.

Consider:

- Running under a dedicated low-privilege user.  
- Using Windows credential vault or other secret storage if you extend the script.

---

## 🧩 Extending the Script

Ideas for future enhancements:

- Optional CSV export of benchmark results.  
- Weighted scoring (e.g., penalize high max latency or jitter).  
- Support for:
  - IPv6-only resolvers  
  - Custom resolver lists supplied via an external file  
- More advanced health checks (error rate thresholds, historical trends).

PRs and forks are welcome if you want to extend this for other environments.

---

## 📜 License

This project is licensed under the **MIT License**.

You are free to:

- Use it  
- Modify it  
- Redistribute it  

as long as the original copyright and license terms are retained.
