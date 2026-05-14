# ⚡ Core365 Event Dashboard v3.2

A modern, interactive **3-pane Windows Event Log Dashboard** built with PowerShell and HTML. Discovers ALL Windows Event Logs — including Application & Services Logs (GPO, PowerShell, DNS, Firewall, etc.) — and generates a self-contained HTML dashboard you can open in any browser.

> **No agents. No servers. No dependencies.** Just run the script and get a full dashboard instantly.

---

## 📸 Screenshot

<img width="1909" height="953" alt="image" src="https://github.com/user-attachments/assets/53529791-8be4-48c2-8466-f359e3847b1f" />


---

## ✨ Features

### 🏗️ 3-Pane Layout
| Pane | Description |
|------|-------------|
| **Left Sidebar** | All discovered event logs in collapsible groups with search filter and event count badges |
| **Middle Pane** | Summary cards → Timeline chart → Correlated Incidents → Filter bar → Events table with pagination |
| **Right Detail Panel** | Click any event row to instantly view full details — click another row to swap without closing |

### 📂 Full Log Discovery
- Uses `Get-WinEvent -ListLog *` to discover **every log** with events
- Includes logs like Group Policy, PowerShell, DNS, NTFS, Firewall, BITS, TaskScheduler, and more
- Logs grouped by category with collapsible tree navigation

### 📚 KB Article Auto-Linking *(NEW in v3.2)*
Every event in the detail panel now shows a **KB / Reference section** with:
- **55 built-in KB entries** covering the most common Windows Event IDs
- **Plain English descriptions** explaining what the event means and what to check
- **Direct Microsoft Docs link** — one click opens the exact Microsoft Learn article
- **Search fallback** — events without a built-in entry get "Search Microsoft Docs" + "Search Google" buttons so you can always find information

#### Built-In KB Coverage

| Category | Event IDs Covered |
|----------|-------------------|
| **Security — Logon/Logoff** | 4624, 4625, 4634, 4648, 4672 |
| **Security — Account Management** | 4720, 4722, 4723, 4724, 4725, 4726 |
| **Security — Group Management** | 4728, 4732, 4733, 4756 |
| **Security — Account Lockout** | 4740, 4767 |
| **Security — Authentication** | 4771, 4776 |
| **Security — Process & Object** | 4688, 4663, 4670, 4697 |
| **Security — Audit** | 1102 |
| **System — Boot/Shutdown** | 41, 6005, 6006, 6008, 6009, 6013 |
| **System — Services** | 7001, 7034, 7036, 7040, 7045 |
| **System — Disk Errors** | 7, 9, 11, 15, 51, 55, 129 |
| **System — Windows Update** | 19, 20, 43 |
| **System — Other** | 104, 1014, 10016 |
| **Application** | 1000, 1001, 1002, 1026 |
| **Group Policy** | 1500, 1501, 1502, 8000, 8001 |
| **Firewall** | 2004, 2005, 2006 |

#### Example KB Entries

| Event ID | Title | What It Tells You |
|----------|-------|-------------------|
| 4625 | Failed Logon | Check sub-status code for specific reason (bad password, expired, locked out) |
| 4740 | Account Locked Out | User locked due to too many failed attempts — check Event 4625 for source |
| 7034 | Service Crashed | A service terminated unexpectedly — check recovery options |
| 1102 | Audit Log Cleared | **Critical** — investigate who cleared the Security log and why |
| 41 | Kernel Power Failure | System rebooted without clean shutdown — power loss, BSOD, or hard reset |
| 55 | NTFS File System Error | File system corrupt — run chkdsk to repair |

### 🔗 Event Correlation (7 Built-In Rules)
Automatically groups related events into **incidents**:

| Rule | Event IDs | Log | Time Window |
|------|-----------|-----|-------------|
| Account Lockout Chain | 4625, 4740, 4767 | Security | 30 min |
| Authentication Failures | 4625, 4771, 4776 | Security | 15 min |
| Service Crash & Recovery | 7034, 7036, 7040 | System | 60 min |
| Group Policy Processing | 1500-1503, 8000-8007 | GPO Operational | 10 min |
| Windows Update | 19, 20, 21, 22, 43, 44 | System | 120 min |
| Disk Errors | 7, 9, 11, 15, 51, 52, 55, 98, 129 | System | 60 min |
| Firewall Changes | 2004, 2005, 2006, 2033 | Firewall | 30 min |

### 🔍 Search & Filtering
- Full-text search with **X clear button** (300ms debounce)
- Filter by Level, Source, and Date Range
- All filters work with AND logic
- "Clear All" button to reset everything

### 📊 Dashboard Components
- **Summary Cards** — Total, Critical, Error, Warning, Information counts
- **Timeline Chart** — Compact events per hour bar chart
- **Sortable Table** — Click column headers to sort ascending/descending
- **Pagination** — 50 events per page with full page controls

### 🎨 UI / UX
- 🌗 **Dark / Light mode** toggle (persists via localStorage)
- **No overlay / grayout** — detail panel slides in without blocking the table
- Color-coded severity badges and row border indicators
- Responsive layout for different screen sizes
- Keyboard support (Escape to close detail panel)

### 📤 Export
- **CSV Export** — exports all currently filtered events to CSV

---

## 📋 Requirements

| Requirement | Details |
|-------------|---------|
| **OS** | Windows 10 / 11 / Server 2016+ |
| **PowerShell** | 5.1 or later (built into Windows) |
| **Permissions** | Run as **Administrator** for Security log access |
| **Browser** | Any modern browser (Chrome, Edge, Firefox) for viewing the dashboard |
| **Network** | Internet connection for Google Fonts and Chart.js CDN (first load only) |

---

## 📥 Installation

1. Download `EventDashboard_v2.ps1`
2. Save it to a folder, e.g., `C:\Scripts\EventDashboard\`
3. That's it — no installation required!

---

## 🚀 Usage

Open **PowerShell as Administrator** and navigate to the script folder:

```powershell
cd C:\Scripts\EventDashboard\
```

### Basic Usage (last 24 hours, all logs)
```powershell
# Run as Admin (for Security log access):
.\EventDashboard_v2.ps1
```

### Custom Time Range
```powershell
# Custom time range:
.\EventDashboard_v2.ps1 -Hours 48
```

### Increase Max Events Per Log
```powershell
# Limit events per log (default 500):
.\EventDashboard_v2.ps1 -MaxEventsPerLog 1000
```

### Custom Output Path
```powershell
.\EventDashboard_v2.ps1 -OutputPath "C:\Reports\EventDashboard.html"
```

### Combine Parameters
```powershell
.\EventDashboard_v2.ps1 -Hours 72 -MaxEventsPerLog 2000 -OutputPath "D:\Logs\weekly_report.html"
```

The dashboard will auto-open in your default browser.

---

## ⚙️ Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Hours` | Int | `24` | Number of hours to look back from current time |
| `-MaxEventsPerLog` | Int | `500` | Maximum events to collect per individual log |
| `-OutputPath` | String | Script directory | Full path for the generated HTML file |

---

## 🖥️ Dashboard Layout

```
┌──────────────────────────────────────────────────────────────────┐
│  ⚡ Core365 Event Dashboard                  Last 24h  🖥 PC  🌓 │
├────────────┬─────────────────────────────────┬───────────────────┤
│            │  [Total] [Critical] [Error]     │                   │
│  📁 Event  │  [Warning] [Information]        │  📋 Event Details │
│  Logs      │                                 │                   │
│            │  📈 Timeline (Events/Hour)      │  Time Created     │
│  ▸ System  │  ▁▂▃▅▇█▅▃▂▁                    │  Event ID         │
│  ▸ Security│                                 │  Level            │
│  ▸ App     │  🔗 Correlated Incidents (3)    │  Log Name         │
│  ▸ GPO     │                                 │  Source           │
│  ▸ DNS     │  🔍 Search  [Filters] [CSV]     │  Machine          │
│  ▸ PS      │                                 │                   │
│  ...       │  Time | ID | Level | Source     │  Full Message     │
│            │  ─────────────────────────      │  (monospace)      │
│            │  row 1                          │                   │
│            │  row 2  ◄── click to view ──►   │  📚 KB Article    │
│            │  row 3                          │  Title & Desc     │
│            │  ...                            │  🔗 MS Docs link  │
│            │  Page 1 of 5 [< 1 2 3 4 5 >]   │  🔍 Search link   │
├────────────┴─────────────────────────────────┴───────────────────┤
│  Core365 Event Dashboard v3.2 | Product by Core365 Cloud         │
└──────────────────────────────────────────────────────────────────┘
```

---

## 📁 Output

The script generates a single self-contained HTML file:

```
Core365_EventDashboard_20260513_084846.html
```

- File name includes timestamp for easy versioning
- Self-contained — all CSS and JavaScript embedded
- Only external dependencies: Google Fonts CDN and Chart.js CDN
- Can be shared, emailed, or archived

---

## 🔄 Version History

| Version | Date | Changes |
|---------|------|---------|
| **v3.2** | 2026-05-13 | 📚 KB article auto-linking with 55 built-in entries, Microsoft Docs direct links, search fallback for unknown events |
| **v3.1** | 2026-05-13 | Compact timeline chart, search X clear button, branding updates |
| **v2.1** | 2026-05-13 | Removed donut chart, smaller timeline, Core365 branding, footer link |
| **v2.0** | 2026-05-13 | 3-pane layout, all log discovery, event correlation, no-overlay detail panel |
| **v1.0** | 2026-05-13 | Initial release — single view, basic filtering, dark/light mode |

---

## 🛡️ Security Notes

- The script **only reads** event logs — it does not modify anything
- All data stays **local** — nothing is sent to any server
- The generated HTML file contains your event log data — treat it as sensitive
- Run as Administrator only if you need Security log access
- KB links open in a new browser tab to Microsoft Learn or Google — no data is transmitted

---

## 🗺️ Roadmap (Future Versions)

- [ ] Multi-server support (query remote machines)
- [ ] Email reports via Microsoft Graph API
- [ ] Scheduled report generation via Task Scheduler
- [ ] Additional correlation rules (DNS, DHCP, Certificate Services)
- [ ] Anomaly detection (spike alerts)
- [ ] Bookmarks / pinning events for follow-up
- [ ] Expand KB database to 200+ Event IDs

---

## 🏢 Author

**Core365 Cloud**
🌐 [https://core365.cloud](https://core365.cloud)

---

## 📄 License

This project is licensed under the **MIT License** — free to use, modify, and distribute.

```
MIT License

Copyright (c) 2026 Core365 Cloud

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
