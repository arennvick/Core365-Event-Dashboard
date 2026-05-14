<#
.SYNOPSIS
    Core365 Event Dashboard - Modern 3-Pane Windows Event Log Dashboard

.DESCRIPTION
    Discovers ALL Windows Event Logs (including Application & Services Logs
    such as GPO, PowerShell, DNS, etc.), collects recent events, and generates
    a self-contained interactive HTML dashboard.

.PARAMETER Hours
    Number of hours to look back. Default: 24.

.PARAMETER MaxEventsPerLog
    Maximum events to collect per individual log. Default: 500.

.PARAMETER OutputPath
    Full path for the generated HTML file.

.EXAMPLE
    .\EventDashboard_v2.ps1
    .\EventDashboard_v2.ps1 -Hours 48
    .\EventDashboard_v2.ps1 -MaxEventsPerLog 1000 -Hours 12

.NOTES
    Author  : Core365 Cloud
    Version : 2.1.0
    Date    : 2026-05-13
#>

[CmdletBinding()]
param(
    [int]    $Hours           = 24,
    [int]    $MaxEventsPerLog = 500,
    [string] $OutputPath      = ""
)

$ErrorActionPreference = 'SilentlyContinue'
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$startTime  = (Get-Date).AddHours(-$Hours)
$genTimeStr = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$pcName     = $env:COMPUTERNAME

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot "Core365_EventDashboard_$timestamp.html"
}

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "     Core365 Event Dashboard - Log Collector v2.1     " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Computer       : $pcName"
Write-Host "  Time Range     : Last $Hours hours (since $($startTime.ToString('yyyy-MM-dd HH:mm')))"
Write-Host "  Max Events/Log : $MaxEventsPerLog"
Write-Host ""

Write-Host "  Discovering event logs..." -ForegroundColor Cyan
$allLogs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
           Where-Object { $_.RecordCount -gt 0 } |
           Sort-Object LogName

$logCount = $allLogs.Count
Write-Host "  Found $logCount logs with events." -ForegroundColor Green
Write-Host ""

$allEvents = [System.Collections.Generic.List[PSObject]]::new()

$levelMap = @{
    0 = 'Information'
    1 = 'Critical'
    2 = 'Error'
    3 = 'Warning'
    4 = 'Information'
    5 = 'Verbose'
}

$collected = 0
$skipped   = 0
$errorLogs = 0

for ($i = 0; $i -lt $allLogs.Count; $i++) {
    $logObj  = $allLogs[$i]
    $logName = $logObj.LogName
    $pct     = [math]::Round(($i / $allLogs.Count) * 100)
    Write-Progress -Activity "Collecting events..." -Status "$logName ($($i+1)/$logCount)" -PercentComplete $pct

    try {
        $filter = @{
            LogName   = $logName
            StartTime = $startTime
        }
        $events = Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEventsPerLog -ErrorAction Stop

        foreach ($evt in $events) {
            $levelName = $evt.LevelDisplayName
            if ([string]::IsNullOrWhiteSpace($levelName)) {
                $lvlInt = [int]$evt.Level
                if ($levelMap.ContainsKey($lvlInt)) {
                    $levelName = $levelMap[$lvlInt]
                } else {
                    $levelName = 'Unknown'
                }
            }

            $msgFull  = if ($evt.Message) { $evt.Message } else { '(No message)' }
            $msgShort = if ($msgFull.Length -gt 500) { $msgFull.Substring(0, 500) + '...' } else { $msgFull }

            $allEvents.Add([PSCustomObject]@{
                TimeCreated  = $evt.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
                Id           = $evt.Id
                Level        = $levelName
                LogName      = $evt.LogName
                Source       = $evt.ProviderName
                MessageShort = $msgShort
                MessageFull  = $msgFull
                MachineName  = $evt.MachineName
            })
        }
        $collected++
    } catch {
        if ($_.Exception.Message -like '*No events were found*') {
            $skipped++
        } else {
            $errorLogs++
        }
    }
}

Write-Progress -Activity "Collecting events..." -Completed
$allEvents = $allEvents | Sort-Object { [datetime]$_.TimeCreated } -Descending
$totalEvents = $allEvents.Count

Write-Host "  Collection complete!" -ForegroundColor Green
Write-Host "    Logs with events : $collected"
Write-Host "    Logs empty       : $skipped"
Write-Host "    Logs errored     : $errorLogs"
Write-Host "    Total events     : $totalEvents"
Write-Host ""

Write-Host "  Building JSON..." -ForegroundColor Cyan
$jsonArray = $allEvents | ForEach-Object {
    @{
        t  = $_.TimeCreated
        id = $_.Id
        lv = $_.Level
        ln = $_.LogName
        sr = $_.Source
        ms = $_.MessageShort
        mf = $_.MessageFull
        mn = $_.MachineName
    }
}

if ($totalEvents -eq 0) {
    $jsonData = "[]"
} elseif ($totalEvents -eq 1) {
    $jsonData = "[" + ($jsonArray | ConvertTo-Json -Depth 3 -Compress) + "]"
} else {
    $jsonData = $jsonArray | ConvertTo-Json -Depth 3 -Compress
}

Write-Host "  Generating HTML dashboard..." -ForegroundColor Cyan

$htmlTemplate = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Core365 Event Dashboard - {{COMPUTER_NAME}}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<style>
:root {
    --bg-primary:#1a1a2e;--bg-sidebar:#121a2e;--bg-card:#16213e;--bg-card-alt:#1a2540;
    --bg-input:#0f3460;--bg-detail:#16213e;--text-primary:#e0e0e0;--text-secondary:#a0aec0;
    --text-muted:#718096;--accent:#0f3460;--highlight:#e94560;--border:#2d3748;
    --critical-clr:#e53e3e;--error-clr:#ed8936;--warning-clr:#ecc94b;--info-clr:#4299e1;
    --success-clr:#48bb78;--shadow:0 4px 20px rgba(0,0,0,0.3);
    --sidebar-w:280px;--detail-w:400px;--header-h:60px;
}
[data-theme="light"] {
    --bg-primary:#f0f2f5;--bg-sidebar:#e8ecf1;--bg-card:#ffffff;--bg-card-alt:#f7fafc;
    --bg-input:#edf2f7;--bg-detail:#ffffff;--text-primary:#1a202c;--text-secondary:#4a5568;
    --text-muted:#a0aec0;--accent:#3182ce;--border:#e2e8f0;--shadow:0 4px 20px rgba(0,0,0,0.08);
}
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:'Inter',-apple-system,BlinkMacSystemFont,sans-serif;background:var(--bg-primary);color:var(--text-primary);transition:background .3s,color .3s;overflow:hidden;height:100vh;}
::-webkit-scrollbar{width:6px;height:6px;}
::-webkit-scrollbar-track{background:transparent;}
::-webkit-scrollbar-thumb{background:var(--border);border-radius:3px;}
::-webkit-scrollbar-thumb:hover{background:var(--text-muted);}
.header{display:flex;justify-content:space-between;align-items:center;padding:0 24px;height:var(--header-h);background:var(--bg-card);border-bottom:1px solid var(--border);box-shadow:var(--shadow);z-index:100;position:relative;}
.header h1{font-size:1.3rem;font-weight:700;white-space:nowrap;}
.header h1 .accent{color:var(--highlight);}
.header-right{display:flex;gap:10px;align-items:center;}
.machine-badge{background:var(--accent);color:#fff;padding:3px 12px;border-radius:16px;font-size:.75rem;font-weight:500;}
.time-badge{font-size:.72rem;color:var(--text-muted);}
.theme-btn{background:var(--bg-input);border:1px solid var(--border);color:var(--text-primary);padding:6px 12px;border-radius:6px;cursor:pointer;font-size:.8rem;transition:all .2s;}
.theme-btn:hover{background:var(--highlight);color:#fff;}
.app-layout{display:flex;height:calc(100vh - var(--header-h));}
.sidebar{width:var(--sidebar-w);min-width:var(--sidebar-w);background:var(--bg-sidebar);border-right:1px solid var(--border);display:flex;flex-direction:column;overflow:hidden;}
.sidebar-header{padding:12px;border-bottom:1px solid var(--border);}
.sidebar-header h3{font-size:.85rem;font-weight:600;margin-bottom:8px;color:var(--text-secondary);}
.sidebar-search{width:100%;background:var(--bg-input);border:1px solid var(--border);color:var(--text-primary);padding:6px 10px;border-radius:6px;font-size:.8rem;font-family:inherit;outline:none;}
.sidebar-search:focus{border-color:var(--highlight);}
.sidebar-tree{flex:1;overflow-y:auto;padding:8px 0;}
.log-group{margin-bottom:2px;}
.log-group-header{display:flex;align-items:center;padding:6px 12px;cursor:pointer;font-size:.78rem;font-weight:600;color:var(--text-secondary);transition:background .15s;}
.log-group-header:hover{background:var(--bg-card-alt);}
.log-group-header .arrow{margin-right:6px;font-size:.65rem;transition:transform .2s;display:inline-block;width:12px;}
.log-group-header .arrow.open{transform:rotate(90deg);}
.log-group-header .grp-count{margin-left:auto;background:var(--bg-input);padding:1px 6px;border-radius:8px;font-size:.65rem;color:var(--text-muted);font-weight:400;}
.log-group-items{display:none;}
.log-group-items.open{display:block;}
.log-item{display:flex;align-items:center;padding:5px 12px 5px 30px;cursor:pointer;font-size:.75rem;color:var(--text-secondary);transition:background .15s;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
.log-item:hover{background:var(--bg-card-alt);}
.log-item.active{background:var(--highlight);color:#fff;font-weight:600;}
.log-item .item-count{margin-left:auto;flex-shrink:0;background:var(--bg-input);padding:1px 6px;border-radius:8px;font-size:.65rem;color:var(--text-muted);font-weight:400;}
.log-item.active .item-count{background:rgba(255,255,255,.2);color:#fff;}
.all-logs-btn{display:flex;align-items:center;padding:8px 12px;margin:0 8px 6px 8px;cursor:pointer;font-size:.8rem;font-weight:600;color:var(--text-primary);background:var(--bg-card);border-radius:8px;transition:background .15s;}
.all-logs-btn:hover{background:var(--bg-card-alt);}
.all-logs-btn.active{background:var(--highlight);color:#fff;}
.all-logs-btn .item-count{margin-left:auto;background:var(--bg-input);padding:1px 8px;border-radius:8px;font-size:.7rem;color:var(--text-muted);}
.all-logs-btn.active .item-count{background:rgba(255,255,255,.2);color:#fff;}
.middle-pane{flex:1;overflow-y:auto;padding:20px;transition:margin-right .3s;}
body.detail-open .middle-pane{margin-right:var(--detail-w);}
.cards{display:grid;grid-template-columns:repeat(5,1fr);gap:12px;margin-bottom:16px;}
.card{background:var(--bg-card);border-radius:10px;padding:14px 16px;box-shadow:var(--shadow);border-left:3px solid var(--border);transition:transform .2s;}
.card:hover{transform:translateY(-1px);}
.card-label{font-size:.7rem;font-weight:500;text-transform:uppercase;color:var(--text-muted);letter-spacing:.4px;}
.card-value{font-size:1.6rem;font-weight:700;margin-top:2px;}
.card.total{border-left-color:var(--accent);}
.card.critical{border-left-color:var(--critical-clr);}.card.critical .card-value{color:var(--critical-clr);}
.card.error{border-left-color:var(--error-clr);}.card.error .card-value{color:var(--error-clr);}
.card.warning{border-left-color:var(--warning-clr);}.card.warning .card-value{color:var(--warning-clr);}
.card.info{border-left-color:var(--info-clr);}.card.info .card-value{color:var(--info-clr);}
.charts{margin-bottom:16px;}
.chart-box{background:var(--bg-card);border-radius:10px;padding:14px;box-shadow:var(--shadow);} .chart-box canvas{max-height:180px;}
.chart-box h3{font-size:.85rem;font-weight:600;margin-bottom:10px;color:var(--text-secondary);}
.corr-section{background:var(--bg-card);border-radius:10px;padding:14px;box-shadow:var(--shadow);margin-bottom:16px;}
.corr-header{display:flex;align-items:center;justify-content:space-between;cursor:pointer;}
.corr-header h3{font-size:.9rem;font-weight:600;color:var(--text-secondary);}
.corr-toggle{font-size:.8rem;color:var(--text-muted);}
.corr-body{margin-top:12px;}
.corr-body.collapsed{display:none;}
.incident-card{background:var(--bg-card-alt);border-radius:8px;padding:12px 14px;margin-bottom:8px;border-left:3px solid var(--border);}
.incident-card.sev-Critical{border-left-color:var(--critical-clr);}
.incident-card.sev-Error{border-left-color:var(--error-clr);}
.incident-card.sev-Warning{border-left-color:var(--warning-clr);}
.incident-card.sev-Information{border-left-color:var(--info-clr);}
.incident-top{display:flex;align-items:center;justify-content:space-between;cursor:pointer;}
.incident-title{font-size:.82rem;font-weight:600;}
.incident-meta{font-size:.72rem;color:var(--text-muted);}
.incident-detail{margin-top:10px;display:none;}
.incident-detail.open{display:block;}
.incident-detail table{width:100%;border-collapse:collapse;font-size:.75rem;}
.incident-detail th{background:var(--bg-input);padding:6px 10px;text-align:left;font-weight:600;color:var(--text-muted);border-bottom:1px solid var(--border);}
.incident-detail td{padding:6px 10px;border-bottom:1px solid var(--border);}
.filter-bar{display:flex;flex-wrap:wrap;gap:10px;align-items:center;background:var(--bg-card);border-radius:10px;padding:12px 14px;box-shadow:var(--shadow);margin-bottom:12px;}
.filter-bar input,.filter-bar select{background:var(--bg-input);border:1px solid var(--border);color:var(--text-primary);padding:6px 12px;border-radius:6px;font-size:.8rem;font-family:inherit;outline:none;}
.filter-bar input:focus,.filter-bar select:focus{border-color:var(--highlight);}
.filter-bar input[type="date"]{min-width:120px;}
.search-wrap{position:relative;min-width:220px;}
.search-wrap input{width:100%;padding-right:28px;}
.search-clear{position:absolute;right:6px;top:50%;transform:translateY(-50%);background:none;border:none;color:var(--text-muted);font-size:1rem;cursor:pointer;padding:0 4px;display:none;line-height:1;}
.search-clear:hover{color:var(--highlight);}
.search-wrap input:not(:placeholder-shown) ~ .search-clear{display:block;}
.btn{padding:6px 14px;border-radius:6px;border:none;cursor:pointer;font-family:inherit;font-size:.8rem;font-weight:500;transition:all .2s;}
.btn-export{background:var(--success-clr);color:#fff;}
.btn-export:hover{background:#38a169;}
.btn-clear{background:var(--text-muted);color:#fff;}
.btn-clear:hover{background:#5a6b7f;}
.filter-count{font-size:.75rem;color:var(--text-muted);margin-left:auto;}
.table-wrap{background:var(--bg-card);border-radius:10px;box-shadow:var(--shadow);overflow:hidden;}
table.evt-table{width:100%;border-collapse:collapse;}
table.evt-table thead th{background:var(--bg-card-alt);padding:10px 12px;text-align:left;font-size:.75rem;font-weight:600;text-transform:uppercase;letter-spacing:.4px;color:var(--text-muted);border-bottom:2px solid var(--border);cursor:pointer;user-select:none;}
table.evt-table thead th:hover{color:var(--highlight);}
table.evt-table thead th .sort-icon{margin-left:4px;font-size:.65rem;}
table.evt-table tbody tr{border-bottom:1px solid var(--border);cursor:pointer;transition:background .12s;}
table.evt-table tbody tr:hover{background:var(--bg-card-alt);}
table.evt-table tbody tr.selected{background:rgba(233,69,96,.12);}
table.evt-table tbody td{padding:8px 12px;font-size:.8rem;vertical-align:top;}
table.evt-table tbody td:first-child{position:relative;padding-left:20px;}
table.evt-table tbody tr[data-level="Critical"] td:first-child::before,
table.evt-table tbody tr[data-level="Error"] td:first-child::before,
table.evt-table tbody tr[data-level="Warning"] td:first-child::before,
table.evt-table tbody tr[data-level="Information"] td:first-child::before{content:'';position:absolute;left:0;top:0;bottom:0;width:3px;}
table.evt-table tbody tr[data-level="Critical"] td:first-child::before{background:var(--critical-clr);}
table.evt-table tbody tr[data-level="Error"] td:first-child::before{background:var(--error-clr);}
table.evt-table tbody tr[data-level="Warning"] td:first-child::before{background:var(--warning-clr);}
table.evt-table tbody tr[data-level="Information"] td:first-child::before{background:var(--info-clr);}
.level-badge{display:inline-block;padding:1px 8px;border-radius:10px;font-size:.7rem;font-weight:600;}
.level-badge.Critical{background:rgba(229,62,62,.15);color:var(--critical-clr);}
.level-badge.Error{background:rgba(237,137,54,.15);color:var(--error-clr);}
.level-badge.Warning{background:rgba(236,201,75,.15);color:var(--warning-clr);}
.level-badge.Information{background:rgba(66,153,225,.15);color:var(--info-clr);}

sg-cell{max-width:320px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
.kb-section{margin-top:16px;padding:14px;background:var(--bg-card-alt);border-radius:8px;border-left:3px solid var(--info-clr);}
.kb-title{font-size:.78rem;font-weight:600;color:var(--text-secondary);margin-bottom:6px;}
.kb-desc{font-size:.82rem;color:var(--text-primary);margin-bottom:8px;line-height:1.5;}
.kb-link{display:inline-block;padding:5px 14px;background:var(--info-clr);color:#fff;border-radius:6px;font-size:.78rem;font-weight:500;text-decoration:none;transition:opacity .2s;}
.kb-link:hover{opacity:.85;}
.kb-link-sec{display:inline-block;padding:5px 14px;background:var(--bg-input);color:var(--text-primary);border:1px solid var(--border);border-radius:6px;font-size:.78rem;font-weight:500;text-decoration:none;margin-left:6px;transition:all .2s;}
.kb-link-sec:hover{border-color:var(--highlight);color:var(--highlight);}

.pagination{display:flex;justify-content:space-between;align-items:center;padding:10px 14px;background:var(--bg-card-alt);border-top:1px solid var(--border);}
.pagination span{font-size:.75rem;color:var(--text-muted);}
.page-btns{display:flex;gap:4px;}
.page-btns button{background:var(--bg-input);border:1px solid var(--border);color:var(--text-primary);padding:4px 10px;border-radius:5px;cursor:pointer;font-size:.75rem;transition:all .2s;}
.page-btns button:hover,.page-btns button.active{background:var(--highlight);color:#fff;border-color:var(--highlight);}
.page-btns button:disabled{opacity:.4;cursor:default;background:var(--bg-input);color:var(--text-primary);}
.detail-panel{position:fixed;top:var(--header-h);right:0;width:var(--detail-w);height:calc(100vh - var(--header-h));background:var(--bg-detail);border-left:1px solid var(--border);box-shadow:-4px 0 20px rgba(0,0,0,.3);transform:translateX(100%);transition:transform .3s ease;z-index:90;display:flex;flex-direction:column;overflow:hidden;}
.detail-panel.open{transform:translateX(0);}
.dp-header{display:flex;justify-content:space-between;align-items:center;padding:14px 16px;border-bottom:1px solid var(--border);flex-shrink:0;}
.dp-header h2{font-size:1rem;font-weight:600;}
.dp-close{background:none;border:none;color:var(--text-primary);font-size:1.2rem;cursor:pointer;padding:4px 8px;border-radius:6px;}
.dp-close:hover{background:var(--highlight);color:#fff;}
.dp-body{padding:16px;overflow-y:auto;flex:1;}
.dp-field{margin-bottom:12px;}
.dp-field-label{font-size:.7rem;font-weight:600;text-transform:uppercase;color:var(--text-muted);letter-spacing:.4px;margin-bottom:3px;}
.dp-field-value{font-size:.85rem;line-height:1.5;word-wrap:break-word;}
.dp-field-value.mono{font-family:'Courier New',monospace;font-size:.78rem;background:var(--bg-primary);padding:10px;border-radius:8px;white-space:pre-wrap;max-height:350px;overflow-y:auto;}
.footer-bar{position:fixed;bottom:0;left:var(--sidebar-w);right:0;text-align:center;padding:6px;font-size:.68rem;color:var(--text-muted);background:var(--bg-card);border-top:1px solid var(--border);z-index:50;}
.footer-bar a{color:var(--highlight);text-decoration:none;}
.footer-bar a:hover{text-decoration:underline;}
@media(max-width:1200px){.cards{grid-template-columns:repeat(3,1fr);}}
@media(max-width:900px){.sidebar{width:220px;min-width:220px;}.cards{grid-template-columns:repeat(2,1fr);}}
</style>
</head>
<body>
<div class="header">
    <h1>&#9889; Core365 Event <span class="accent">Dashboard</span> <small style="font-size:.6rem;color:var(--text-muted)">v4.0</small></h1>
    <div class="header-right">
        <span class="time-badge">Last {{HOURS}} hours</span>
        <span class="machine-badge">&#128421; {{COMPUTER_NAME}}</span>
        <button class="theme-btn" onclick="toggleTheme()" title="Toggle theme">&#127763; Theme</button>
    </div>
</div>
<div class="app-layout">
    <div class="sidebar">
        <div class="sidebar-header">
            <h3>&#128194; Event Logs</h3>
            <input type="text" class="sidebar-search" id="sidebarSearch" placeholder="&#128269; Filter logs..." oninput="filterSidebar()">
        </div>
        <div class="sidebar-tree" id="sidebarTree"></div>
    </div>
    <div class="middle-pane" id="middlePane">
        <div style="margin-bottom:14px;"><h2 id="selectedLogTitle" style="font-size:1.1rem;font-weight:700;">All Logs</h2></div>
        <div class="cards">
            <div class="card total"><div class="card-label">Total</div><div class="card-value" id="cTotal">0</div></div>
            <div class="card critical"><div class="card-label">Critical</div><div class="card-value" id="cCritical">0</div></div>
            <div class="card error"><div class="card-label">Error</div><div class="card-value" id="cError">0</div></div>
            <div class="card warning"><div class="card-label">Warning</div><div class="card-value" id="cWarning">0</div></div>
            <div class="card info"><div class="card-label">Information</div><div class="card-value" id="cInfo">0</div></div>
        </div>
        <div class="charts">
            <div class="chart-box"><h3>&#128200; Timeline (Events/Hour)</h3><canvas id="timelineChart" height="45"></canvas></div>
        </div>
        <div class="corr-section" id="corrSection">
            <div class="corr-header" onclick="toggleCorrelations()">
                <h3>&#128279; Correlated Incidents <span id="corrCount" style="font-size:.75rem;color:var(--text-muted)">(0)</span></h3>
                <span class="corr-toggle" id="corrToggle">&#9660; Show</span>
            </div>
            <div class="corr-body collapsed" id="corrBody"></div>
        </div>
        <div class="filter-bar">
            <div class="search-wrap">
                <input type="text" id="fSearch" placeholder="&#128269; Search..." oninput="debounceFilter()">
                <button class="search-clear" id="searchClear" onclick="clearSearch()" title="Clear search">&#10005;</button>
            </div>
            <select id="fLevel" onchange="applyFilters()"><option value="">All Levels</option></select>
            <select id="fSource" onchange="applyFilters()"><option value="">All Sources</option></select>
            <input type="date" id="fDateFrom" onchange="applyFilters()" title="From">
            <input type="date" id="fDateTo" onchange="applyFilters()" title="To">
            <button class="btn btn-clear" onclick="clearFilters()">&#10005; Clear All</button>
            <button class="btn btn-export" onclick="exportCSV()">&#128228; CSV</button>
            <span class="filter-count" id="filterCount"></span>
        </div>
        <div class="table-wrap">
            <table class="evt-table">
                <thead><tr>
                    <th onclick="sortBy('t')">Time <span class="sort-icon" id="sort_t"></span></th>
                    <th onclick="sortBy('id')">ID <span class="sort-icon" id="sort_id"></span></th>
                    <th onclick="sortBy('lv')">Level <span class="sort-icon" id="sort_lv"></span></th>
                    <th onclick="sortBy('ln')">Log <span class="sort-icon" id="sort_ln"></span></th>
                    <th onclick="sortBy('sr')">Source <span class="sort-icon" id="sort_sr"></span></th>
                    <th onclick="sortBy('ms')">Message <span class="sort-icon" id="sort_ms"></span></th>
                </tr></thead>
                <tbody id="eventBody"></tbody>
            </table>
            <div class="pagination">
                <span id="pageInfo">Page 1 of 1</span>
                <div class="page-btns" id="pageBtns"></div>
            </div>
        </div>
        <div style="height:40px;"></div>
    </div>
</div>
<div class="detail-panel" id="detailPanel">
    <div class="dp-header">
        <h2>&#128203; Event Details</h2>
        <button class="dp-close" onclick="closeDetail()">&#10005;</button>
    </div>
    <div class="dp-body" id="dpBody">
        <p style="color:var(--text-muted);font-size:.85rem;">Click an event to view details.</p>
    </div>
</div>
<div class="footer-bar">
    Product by <a href="https://core365.cloud" target="_blank">Core365 Event Dashboard v4.0</a> &nbsp;|&nbsp; Generated {{GEN_TIME}} &nbsp;|&nbsp; {{COMPUTER_NAME}}
</div>
<script>
var DATA={{JSON_DATA}};
var activeLog='',logFiltered=[],filtered=[],currentPage=1,pageSize=50,sortCol='t',sortAsc=false,debounceTimer=null,selectedRowIdx=-1,timelineChart=null,corrExpanded=false,incidents=[];
var CORR_RULES=[
{name:'Account Lockout Chain',desc:'Failed logon attempts leading to account lockout and unlock',ids:[4625,4740,4767],log:'Security',regex:/Account Name:\s+(\S+)/i,windowMin:30},
{name:'Authentication Failures',desc:'Repeated authentication failures (Kerberos, NTLM)',ids:[4625,4771,4776],log:'Security',regex:/Account Name:\s+(\S+)/i,windowMin:15},
{name:'Service Crash & Recovery',desc:'Service unexpected termination and state changes',ids:[7034,7036,7040],log:'System',regex:/service|The (.*?) service/i,windowMin:60},
{name:'Group Policy Processing',desc:'GPO apply cycle events',ids:[1500,1501,1502,1503,8000,8001,8002,8003,8004,8005,8006,8007],log:'Microsoft-Windows-GroupPolicy/Operational',regex:/./,windowMin:10},
{name:'Windows Update',desc:'Update installation, restart required, and failure events',ids:[19,20,21,22,43,44],log:'System',regex:/KB\d+|Update|update/i,windowMin:120},
{name:'Disk Errors',desc:'Disk I/O errors, bad blocks, controller resets',ids:[7,9,11,15,51,52,55,98,129],log:'System',regex:/\\\\Device\\\\(\S+)/i,windowMin:60},
{name:'Firewall Changes',desc:'Windows Firewall rule additions, deletions, and changes',ids:[2004,2005,2006,2033],log:'Microsoft-Windows-Windows Firewall With Advanced Security/Firewall',regex:/Rule Name:\s+(.+)/i,windowMin:30}
];
var KB_MAP={
4624:{t:'Successful Logon',d:'An account was successfully logged on. Review logon type to determine if interactive, network, or service logon.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4624'},
4625:{t:'Failed Logon',d:'An account failed to log on. Check sub-status code for the specific reason (bad password, expired account, locked out, etc.).',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4625'},
4634:{t:'Account Logoff',d:'An account was logged off. Correlate with Event 4624 using Logon ID to determine session duration.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4634'},
4648:{t:'Logon Using Explicit Credentials',d:'A logon was attempted using explicit credentials (RunAs). Review which account was used and the target server.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4648'},
4672:{t:'Special Privileges Assigned',d:'Special privileges (e.g., SeDebugPrivilege, SeBackupPrivilege) were assigned to a new logon. Normal for admin accounts.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4672'},
4688:{t:'New Process Created',d:'A new process was created. When command line auditing is enabled, shows the full command. Critical for threat hunting.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4688'},
4720:{t:'User Account Created',d:'A new user account was created. Review who created it and verify it was authorized.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4720'},
4722:{t:'User Account Enabled',d:'A user account was enabled. Verify this was an authorized administrative action.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4722'},
4723:{t:'Password Change Attempt',d:'An attempt was made to change an account password. The user supplied the old password.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4723'},
4724:{t:'Password Reset Attempt',d:'An attempt was made to reset an account password by an administrator.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4724'},
4725:{t:'User Account Disabled',d:'A user account was disabled. Common during offboarding or security incidents.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4725'},
4726:{t:'User Account Deleted',d:'A user account was deleted. Verify this was an authorized administrative action.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4726'},
4728:{t:'Member Added to Security Group',d:'A member was added to a security-enabled global group. Review the group and member.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4728'},
4732:{t:'Member Added to Local Group',d:'A member was added to a security-enabled local group (e.g., Administrators).',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4732'},
4733:{t:'Member Removed from Local Group',d:'A member was removed from a security-enabled local group.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4733'},
4740:{t:'Account Locked Out',d:'A user account was locked out due to too many failed logon attempts. Check Event 4625 for the source of bad passwords.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4740'},
4756:{t:'Member Added to Universal Group',d:'A member was added to a security-enabled universal group.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4756'},
4767:{t:'Account Unlocked',d:'A user account was unlocked by an administrator.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4767'},
4771:{t:'Kerberos Pre-Authentication Failed',d:'Kerberos pre-authentication failed. Common causes: wrong password, clock skew, or disabled account.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4771'},
4776:{t:'NTLM Authentication (Credential Validation)',d:'The domain controller attempted to validate credentials via NTLM. Error code 0xC000006A = bad password.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4776'},
4663:{t:'Object Access Attempt',d:'An attempt was made to access an object (file, registry, etc.). Requires auditing enabled on the object.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4663'},
4670:{t:'Permissions Changed on Object',d:'Permissions on an object were changed. Shows old and new security descriptors.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4670'},
1102:{t:'Audit Log Cleared',d:'The Security audit log was cleared. This is a critical event — investigate who cleared it and why.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-1102'},
4697:{t:'Service Installed',d:'A service was installed in the system. Review the service name and path for malicious installations.',u:'https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4697'},
41:{t:'Unexpected Kernel Power Failure',d:'The system rebooted without cleanly shutting down. Causes: power loss, BSOD, hard reset, or hung system.',u:'https://learn.microsoft.com/en-us/search/?terms=event+41+kernel+power'},
104:{t:'Event Log Cleared',d:'An event log was cleared. Check who performed the action and verify it was authorized.',u:'https://learn.microsoft.com/en-us/search/?terms=event+104+log+cleared'},
1014:{t:'DNS Resolution Timeout',d:'Name resolution for a DNS name timed out after none of the configured DNS servers responded.',u:'https://learn.microsoft.com/en-us/search/?terms=event+1014+dns+client'},
6005:{t:'Event Log Service Started',d:'The Event Log service was started. Indicates system boot or service restart.',u:'https://learn.microsoft.com/en-us/search/?terms=event+6005+eventlog+started'},
6006:{t:'Event Log Service Stopped',d:'The Event Log service was stopped. Indicates clean system shutdown.',u:'https://learn.microsoft.com/en-us/search/?terms=event+6006+eventlog+stopped'},
6008:{t:'Unexpected Shutdown',d:'The previous system shutdown was unexpected. Correlate with Event 41 (Kernel-Power).',u:'https://learn.microsoft.com/en-us/search/?terms=event+6008+unexpected+shutdown'},
6009:{t:'OS Version at Boot',d:'Logged at boot time showing the Windows version, build, and service pack.',u:'https://learn.microsoft.com/en-us/search/?terms=event+6009+os+version+boot'},
6013:{t:'System Uptime',d:'Shows system uptime in seconds. Useful for tracking reboot schedules and unplanned restarts.',u:'https://learn.microsoft.com/en-us/search/?terms=event+6013+system+uptime'},
7001:{t:'Service Logon Failure',d:'A service failed to log on. Check the service account credentials and permissions.',u:'https://learn.microsoft.com/en-us/search/?terms=event+7001+service+logon+failure'},
7034:{t:'Service Crashed Unexpectedly',d:'A service terminated unexpectedly. Check the service recovery options and application logs.',u:'https://learn.microsoft.com/en-us/search/?terms=event+7034+service+terminated+unexpectedly'},
7036:{t:'Service State Change',d:'A service entered the running or stopped state. Normal operational event.',u:'https://learn.microsoft.com/en-us/search/?terms=event+7036+service+control+manager'},
7040:{t:'Service Start Type Changed',d:'The start type of a service was changed (e.g., from Automatic to Disabled).',u:'https://learn.microsoft.com/en-us/search/?terms=event+7040+service+start+type+changed'},
7045:{t:'New Service Installed',d:'A new service was installed in the system. Review for unauthorized service installations.',u:'https://learn.microsoft.com/en-us/search/?terms=event+7045+new+service+installed'},
10016:{t:'DCOM Permission Error',d:'DCOM server launch/activation permission error. Often benign but can indicate permission misconfiguration.',u:'https://learn.microsoft.com/en-us/search/?terms=event+10016+distributedcom'},
1000:{t:'Application Error',d:'An application faulted. Check the faulting module name and offset for debugging.',u:'https://learn.microsoft.com/en-us/search/?terms=event+1000+application+error'},
1001:{t:'Windows Error Reporting',d:'A fault bucket report was generated. Contains crash details for analysis.',u:'https://learn.microsoft.com/en-us/search/?terms=event+1001+windows+error+reporting'},
1002:{t:'Application Hang',d:'An application stopped responding and was closed. Check for resource exhaustion.',u:'https://learn.microsoft.com/en-us/search/?terms=event+1002+application+hang'},
1026:{t:'.NET Runtime Error',d:'An unhandled .NET exception occurred. Review the stack trace in the event message.',u:'https://learn.microsoft.com/en-us/search/?terms=event+1026+.net+runtime+error'},
1500:{t:'GP: No Changes Detected',d:'Group Policy processing found no changes. Policies are already applied.',u:'https://learn.microsoft.com/en-us/search/?terms=event+1500+group+policy+no+changes'},
1501:{t:'GP: Applied Successfully',d:'Group Policy was applied successfully. Check processing time for performance issues.',u:'https://learn.microsoft.com/en-us/search/?terms=event+1501+group+policy+applied'},
1502:{t:'GP: Processing Failed',d:'Group Policy processing failed. Check network connectivity and DC availability.',u:'https://learn.microsoft.com/en-us/search/?terms=event+1502+group+policy+failed'},
8000:{t:'GP: Start Processing',d:'Group Policy processing started for the computer or user.',u:'https://learn.microsoft.com/en-us/search/?terms=event+8000+group+policy+processing'},
8001:{t:'GP: Completed Processing',d:'Group Policy processing completed successfully.',u:'https://learn.microsoft.com/en-us/search/?terms=event+8001+group+policy+completed'},
19:{t:'Windows Update Installed',d:'A Windows Update was successfully installed.',u:'https://learn.microsoft.com/en-us/search/?terms=event+19+windows+update+installed'},
20:{t:'Windows Update Install Failed',d:'A Windows Update installation failed. Check the error code for details.',u:'https://learn.microsoft.com/en-us/search/?terms=event+20+windows+update+failed'},
43:{t:'Windows Update Download Started',d:'Windows Update started downloading an update.',u:'https://learn.microsoft.com/en-us/search/?terms=event+43+windows+update+download'},
2004:{t:'Firewall Rule Added',d:'A rule was added to the Windows Firewall exception list.',u:'https://learn.microsoft.com/en-us/search/?terms=event+2004+firewall+rule+added'},
2005:{t:'Firewall Rule Modified',d:'A Windows Firewall rule was modified.',u:'https://learn.microsoft.com/en-us/search/?terms=event+2005+firewall+rule+modified'},
2006:{t:'Firewall Rule Deleted',d:'A Windows Firewall rule was deleted.',u:'https://learn.microsoft.com/en-us/search/?terms=event+2006+firewall+rule+deleted'},
7:{t:'Disk Bad Block / Device Error',d:'The device has a bad block or an I/O error occurred. Check disk health immediately.',u:'https://learn.microsoft.com/en-us/search/?terms=event+7+disk+bad+block'},
9:{t:'Disk Controller Error',d:'The device is not ready for access. May indicate hardware failure.',u:'https://learn.microsoft.com/en-us/search/?terms=event+9+disk+controller+error'},
11:{t:'Disk Controller Error',d:'The driver detected a controller error on a device. Check disk and cable connections.',u:'https://learn.microsoft.com/en-us/search/?terms=event+11+disk+controller+error'},
15:{t:'Disk Not Ready',d:'The device is not ready for access yet. May occur during boot or hot-plug events.',u:'https://learn.microsoft.com/en-us/search/?terms=event+15+disk+not+ready'},
51:{t:'Disk Paging Error',d:'An error was detected on device during a paging operation. Indicates potential disk failure.',u:'https://learn.microsoft.com/en-us/search/?terms=event+51+disk+paging+error'},
55:{t:'NTFS File System Error',d:'The NTFS file system structure is corrupt. Run chkdsk to repair.',u:'https://learn.microsoft.com/en-us/search/?terms=event+55+ntfs+file+system+corrupt'},
129:{t:'Disk Reset',d:'A disk device reset was issued. Often related to storage controller timeouts.',u:'https://learn.microsoft.com/en-us/search/?terms=event+129+disk+reset+storahci'}
};
function getKbInfo(id){var num=Number(id);if(KB_MAP.hasOwnProperty(num)){return KB_MAP[num];}return null;}
function getKbSearchUrl(id,source){return 'https://learn.microsoft.com/en-us/search/?terms=Event+ID+'+id+'+'+encodeURIComponent(source);}
function getEventIdNetUrl(id){return 'https://www.google.com/search?q=Event+ID+'+id+'+Windows+site%3Alearn.microsoft.com';}
document.addEventListener('DOMContentLoaded',function(){var saved=localStorage.getItem('ed-theme');if(saved==='light')document.documentElement.setAttribute('data-theme','light');buildLogTree();selectLog('');buildCorrelations();renderCorrelations();});
function toggleTheme(){var curr=document.documentElement.getAttribute('data-theme');var next=(curr==='light')?'':'light';document.documentElement.setAttribute('data-theme',next);localStorage.setItem('ed-theme',next||'dark');buildChartsForFiltered();}
function buildLogTree(){var lc={};for(var i=0;i<DATA.length;i++){var ln=DATA[i].ln;lc[ln]=(lc[ln]||0)+1;}var groups={};var names=Object.keys(lc).sort();for(var j=0;j<names.length;j++){var full=names[j];var si=full.lastIndexOf('/');var cat,sub;if(si>-1){cat=full.substring(0,si);sub=full.substring(si+1);}else{cat=full;sub='';}if(!groups[cat])groups[cat]=[];groups[cat].push({full:full,sub:sub,count:lc[full]});}var html='<div class="all-logs-btn active" id="allLogsBtn" onclick="selectLog(\'\')">&#128202; All Logs<span class="item-count">'+DATA.length+'</span></div>';var ck=Object.keys(groups).sort();for(var k=0;k<ck.length;k++){var cn=ck[k];var items=groups[cn];var gt=0;for(var m=0;m<items.length;m++)gt+=items[m].count;var gid='grp_'+k;html+='<div class="log-group" data-cat="'+esc(cn.toLowerCase())+'">';html+='<div class="log-group-header" onclick="toggleGroup(\''+gid+'\')">';html+='<span class="arrow" id="arrow_'+gid+'">&#9654;</span>';html+='<span style="flex:1;overflow:hidden;text-overflow:ellipsis;" title="'+esc(cn)+'">'+esc(cn)+'</span>';html+='<span class="grp-count">'+gt+'</span></div>';html+='<div class="log-group-items" id="'+gid+'">';for(var n=0;n<items.length;n++){var it=items[n];var lb=it.sub?it.sub:it.full;html+='<div class="log-item" data-log="'+esc(it.full)+'" onclick="selectLog(\''+escJs(it.full)+'\')" title="'+esc(it.full)+'">'+esc(lb)+'<span class="item-count">'+it.count+'</span></div>';}html+='</div></div>';}document.getElementById('sidebarTree').innerHTML=html;}
function toggleGroup(gid){var el=document.getElementById(gid);var ar=document.getElementById('arrow_'+gid);if(el.classList.contains('open')){el.classList.remove('open');ar.classList.remove('open');}else{el.classList.add('open');ar.classList.add('open');}}
function filterSidebar(){var q=document.getElementById('sidebarSearch').value.toLowerCase();var gs=document.querySelectorAll('.log-group');for(var i=0;i<gs.length;i++){var cat=gs[i].getAttribute('data-cat')||'';var items=gs[i].querySelectorAll('.log-item');var any=false;for(var j=0;j<items.length;j++){var nm=(items[j].getAttribute('data-log')||'').toLowerCase();if(!q||nm.indexOf(q)>-1||cat.indexOf(q)>-1){items[j].style.display='';any=true;}else{items[j].style.display='none';}}gs[i].style.display=any?'':'none';if(q&&any){var gid=gs[i].querySelector('.log-group-items').id;document.getElementById(gid).classList.add('open');document.getElementById('arrow_'+gid).classList.add('open');}}}
function selectLog(logName){activeLog=logName;var ab=document.getElementById('allLogsBtn');if(!logName){ab.classList.add('active');}else{ab.classList.remove('active');}var li=document.querySelectorAll('.log-item');for(var i=0;i<li.length;i++){if(li[i].getAttribute('data-log')===logName){li[i].classList.add('active');}else{li[i].classList.remove('active');}}document.getElementById('selectedLogTitle').textContent=logName||'All Logs';if(logName){logFiltered=[];for(var j=0;j<DATA.length;j++){if(DATA[j].ln===logName)logFiltered.push(DATA[j]);}}else{logFiltered=DATA.slice();}populateDropdowns();clearFiltersQuiet();applyFilters();buildChartsForFiltered();}
function populateDropdowns(){var ls={},ss={};for(var i=0;i<logFiltered.length;i++){ls[logFiltered[i].lv]=true;ss[logFiltered[i].sr]=true;}var lk=Object.keys(ls).sort();var sk=Object.keys(ss).sort().slice(0,100);var fl=document.getElementById('fLevel');fl.innerHTML='<option value="">All Levels</option>';addOpts(fl,lk);var fs=document.getElementById('fSource');fs.innerHTML='<option value="">All Sources</option>';addOpts(fs,sk);}
function addOpts(sel,vals){for(var i=0;i<vals.length;i++){var o=document.createElement('option');o.value=vals[i];o.textContent=vals[i];sel.appendChild(o);}}
function debounceFilter(){clearTimeout(debounceTimer);debounceTimer=setTimeout(applyFilters,300);}
function clearSearch(){document.getElementById('fSearch').value='';applyFilters();}
function applyFilters(){var search=document.getElementById('fSearch').value.toLowerCase();var level=document.getElementById('fLevel').value;var source=document.getElementById('fSource').value;var df=document.getElementById('fDateFrom').value;var dt=document.getElementById('fDateTo').value;filtered=[];for(var i=0;i<logFiltered.length;i++){var e=logFiltered[i];if(level&&e.lv!==level)continue;if(source&&e.sr!==source)continue;if(df&&e.t.substring(0,10)<df)continue;if(dt&&e.t.substring(0,10)>dt)continue;if(search){var hay=(e.t+' '+e.id+' '+e.lv+' '+e.ln+' '+e.sr+' '+e.ms).toLowerCase();if(hay.indexOf(search)===-1)continue;}filtered.push(e);}applySorting();currentPage=1;selectedRowIdx=-1;renderTable();updateCards();document.getElementById('filterCount').textContent='Showing '+filtered.length+' of '+logFiltered.length;}
function clearFilters(){clearFiltersQuiet();applyFilters();}
function clearFiltersQuiet(){document.getElementById('fSearch').value='';document.getElementById('fLevel').value='';document.getElementById('fSource').value='';document.getElementById('fDateFrom').value='';document.getElementById('fDateTo').value='';}
function sortBy(col){if(sortCol===col){sortAsc=!sortAsc;}else{sortCol=col;sortAsc=true;}applySorting();renderTable();var ic=document.querySelectorAll('.sort-icon');for(var i=0;i<ic.length;i++)ic[i].textContent='';var ai=document.getElementById('sort_'+col);if(ai)ai.textContent=sortAsc?'\u25B2':'\u25BC';}
function applySorting(){filtered.sort(function(a,b){var va=a[sortCol],vb=b[sortCol];if(sortCol==='id'){va=Number(va);vb=Number(vb);}else{va=String(va).toLowerCase();vb=String(vb).toLowerCase();}if(va<vb)return sortAsc?-1:1;if(va>vb)return sortAsc?1:-1;return 0;});}
function renderTable(){var tb=document.getElementById('eventBody');var tp=Math.max(1,Math.ceil(filtered.length/pageSize));if(currentPage>tp)currentPage=tp;var st=(currentPage-1)*pageSize;var pg=filtered.slice(st,st+pageSize);var html='';for(var i=0;i<pg.length;i++){var e=pg[i];var gi=st+i;var mt=e.ms.length>100?e.ms.substring(0,100)+'...':e.ms;var sl=(gi===selectedRowIdx)?' selected':'';html+='<tr data-level="'+esc(e.lv)+'" class="'+sl+'" onclick="openDetail('+gi+')"><td>'+esc(e.t)+'</td><td>'+esc(String(e.id))+'</td><td><span class="level-badge '+esc(e.lv)+'">'+esc(e.lv)+'</span></td><td style="max-width:140px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" title="'+esc(e.ln)+'">'+esc(e.ln)+'</td><td style="max-width:140px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" title="'+esc(e.sr)+'">'+esc(e.sr)+'</td><td class="msg-cell" title="'+esc(e.ms)+'">'+esc(mt)+'</td></tr>';}tb.innerHTML=html;renderPagination(tp);}
function renderPagination(tp){document.getElementById('pageInfo').textContent='Page '+currentPage+' of '+tp+' ('+filtered.length+' events)';var bt=document.getElementById('pageBtns');var h='<button onclick="goPage(1)"'+(currentPage===1?' disabled':'')+'>&laquo;</button>';h+='<button onclick="goPage('+(currentPage-1)+')"'+(currentPage===1?' disabled':'')+'>&lsaquo;</button>';var s=Math.max(1,currentPage-3),en=Math.min(tp,currentPage+3);for(var p=s;p<=en;p++){h+='<button onclick="goPage('+p+')"'+(p===currentPage?' class="active"':'')+'>' +p+'</button>';}h+='<button onclick="goPage('+(currentPage+1)+')"'+(currentPage===tp?' disabled':'')+'>&rsaquo;</button>';h+='<button onclick="goPage('+tp+')"'+(currentPage===tp?' disabled':'')+'>&raquo;</button>';bt.innerHTML=h;}
function goPage(p){currentPage=p;renderTable();document.querySelector('.table-wrap').scrollIntoView({behavior:'smooth',block:'nearest'});}
function updateCards(){var c={Critical:0,Error:0,Warning:0,Information:0};for(var i=0;i<filtered.length;i++){var l=filtered[i].lv;if(c.hasOwnProperty(l))c[l]++;}document.getElementById('cTotal').textContent=filtered.length.toLocaleString();document.getElementById('cCritical').textContent=c.Critical.toLocaleString();document.getElementById('cError').textContent=c.Error.toLocaleString();document.getElementById('cWarning').textContent=c.Warning.toLocaleString();document.getElementById('cInfo').textContent=c.Information.toLocaleString();}
function openDetail(idx){var e=filtered[idx];if(!e)return;selectedRowIdx=idx;var fields=[{l:'Time Created',v:e.t},{l:'Event ID',v:String(e.id)},{l:'Level',v:e.lv},{l:'Log Name',v:e.ln},{l:'Source',v:e.sr},{l:'Machine',v:e.mn},{l:'Full Message',v:e.mf,mono:true}];var html='';for(var i=0;i<fields.length;i++){var f=fields[i];html+='<div class="dp-field"><div class="dp-field-label">'+esc(f.l)+'</div><div class="dp-field-value'+(f.mono?' mono':'')+'">'+esc(f.v)+'</div></div>';}var kb=getKbInfo(e.id);html+='<div class="kb-section"><div class="kb-title">&#128218; KB Article / Reference</div>';if(kb){html+='<div class="kb-desc"><strong>'+esc(kb.t)+'</strong><br>'+esc(kb.d)+'</div>';html+='<a class="kb-link" href="'+kb.u+'" target="_blank" rel="noopener">&#128279; View Microsoft Docs</a>';html+='<a class="kb-link-sec" href="'+getKbSearchUrl(e.id,e.sr)+'" target="_blank" rel="noopener">&#128269; Search More</a>';}else{html+='<div class="kb-desc">No built-in KB entry for Event ID '+esc(String(e.id))+'. Click below to search.</div>';html+='<a class="kb-link" href="'+getKbSearchUrl(e.id,e.sr)+'" target="_blank" rel="noopener">&#128269; Search Microsoft Docs</a>';html+='<a class="kb-link-sec" href="'+getEventIdNetUrl(e.id)+'" target="_blank" rel="noopener">&#127760; Search Google</a>';}html+='</div>';document.getElementById('dpBody').innerHTML=html;var panel=document.getElementById('detailPanel');if(!panel.classList.contains('open')){panel.classList.add('open');document.body.classList.add('detail-open');}renderTable();}
function closeDetail(){document.getElementById('detailPanel').classList.remove('open');document.body.classList.remove('detail-open');selectedRowIdx=-1;renderTable();}
document.addEventListener('keydown',function(e){if(e.key==='Escape')closeDetail();});
function buildChartsForFiltered(){var isDark=document.documentElement.getAttribute('data-theme')!=='light';var gClr=isDark?'rgba(255,255,255,0.08)':'rgba(0,0,0,0.08)';var tClr=isDark?'#a0aec0':'#4a5568';var src=filtered.length>0?filtered:logFiltered;var hMap={};for(var i=0;i<src.length;i++){var hk=src[i].t.substring(0,13)+':00';hMap[hk]=(hMap[hk]||0)+1;}var sH=Object.keys(hMap).sort();var hC=[];for(var h=0;h<sH.length;h++)hC.push(hMap[sH[h]]);if(timelineChart)timelineChart.destroy();timelineChart=new Chart(document.getElementById('timelineChart'),{type:'bar',data:{labels:sH,datasets:[{label:'Events',data:hC,backgroundColor:'rgba(233,69,96,0.7)',borderRadius:3}]},options:{responsive:true,maintainAspectRatio:true,plugins:{legend:{display:false}},scales:{x:{ticks:{color:tClr,maxRotation:45,maxTicksLimit:24},grid:{color:gClr}},y:{ticks:{color:tClr},grid:{color:gClr},beginAtZero:true}}}});}
function buildCorrelations(){incidents=[];var sev={Critical:0,Error:1,Warning:2,Information:3,Verbose:4,Unknown:5};for(var r=0;r<CORR_RULES.length;r++){var rule=CORR_RULES[r];var mt=[];for(var i=0;i<DATA.length;i++){var ev=DATA[i];if(rule.ids.indexOf(ev.id)===-1)continue;if(rule.log&&rule.log!=='*'&&ev.ln!==rule.log)continue;var gk='default';if(rule.regex){var m=rule.regex.exec(ev.mf||ev.ms||'');if(m&&m[1])gk=m[1].substring(0,60);}mt.push({ev:ev,gk:gk});}if(mt.length===0)continue;var groups={};for(var g=0;g<mt.length;g++){var key=mt[g].gk;if(!groups[key])groups[key]=[];groups[key].push(mt[g].ev);}var gKeys=Object.keys(groups);for(var x=0;x<gKeys.length;x++){var evts=groups[gKeys[x]];if(evts.length<2)continue;evts.sort(function(a,b){return a.t<b.t?-1:a.t>b.t?1:0;});var first=new Date(evts[0].t.replace(' ','T'));var last=new Date(evts[evts.length-1].t.replace(' ','T'));var diff=(last-first)/60000;if(diff<=rule.windowMin){var hs='Information';for(var sv=0;sv<evts.length;sv++){if((sev[evts[sv].lv]||5)<(sev[hs]||5))hs=evts[sv].lv;}incidents.push({rule:rule.name,desc:rule.desc,groupKey:gKeys[x],events:evts,firstTime:evts[0].t,lastTime:evts[evts.length-1].t,severity:hs,count:evts.length});}}}incidents.sort(function(a,b){var sa=sev[a.severity]||5;var sb=sev[b.severity]||5;if(sa!==sb)return sa-sb;return a.firstTime>b.firstTime?-1:1;});}
function renderCorrelations(){document.getElementById('corrCount').textContent='('+incidents.length+')';if(incidents.length===0){document.getElementById('corrBody').innerHTML='<p style="font-size:.82rem;color:var(--text-muted);padding:6px 0;">No correlated incidents detected.</p>';return;}var html='';for(var i=0;i<incidents.length;i++){var inc=incidents[i];var iid='inc_'+i;html+='<div class="incident-card sev-'+esc(inc.severity)+'">';html+='<div class="incident-top" onclick="toggleIncident(\''+iid+'\')">';html+='<div><span class="incident-title">'+esc(inc.rule)+'</span><br><span class="incident-meta">'+esc(inc.desc)+' | Group: '+esc(inc.groupKey)+'</span></div>';html+='<div style="text-align:right;"><span class="level-badge '+esc(inc.severity)+'">'+esc(inc.severity)+'</span><br><span class="incident-meta">'+inc.count+' events | '+esc(inc.firstTime)+' - '+esc(inc.lastTime)+'</span></div>';html+='</div><div class="incident-detail" id="'+iid+'"><table><thead><tr><th>Time</th><th>ID</th><th>Level</th><th>Source</th><th>Message</th></tr></thead><tbody>';for(var j=0;j<inc.events.length;j++){var ev=inc.events[j];var ms=ev.ms.length>80?ev.ms.substring(0,80)+'...':ev.ms;html+='<tr><td>'+esc(ev.t)+'</td><td>'+esc(String(ev.id))+'</td><td><span class="level-badge '+esc(ev.lv)+'">'+esc(ev.lv)+'</span></td><td>'+esc(ev.sr)+'</td><td>'+esc(ms)+'</td></tr>';}html+='</tbody></table></div></div>';}document.getElementById('corrBody').innerHTML=html;}
function toggleCorrelations(){var body=document.getElementById('corrBody');var tog=document.getElementById('corrToggle');corrExpanded=!corrExpanded;if(corrExpanded){body.classList.remove('collapsed');tog.innerHTML='&#9650; Hide';}else{body.classList.add('collapsed');tog.innerHTML='&#9660; Show';}}
function toggleIncident(iid){var el=document.getElementById(iid);if(el.classList.contains('open')){el.classList.remove('open');}else{el.classList.add('open');}}
function exportCSV(){var hdr='Time,EventID,Level,LogName,Source,MachineName,Message\n';var rows='';for(var i=0;i<filtered.length;i++){var e=filtered[i];rows+=e.t+','+e.id+','+csvSafe(e.lv)+','+csvSafe(e.ln)+','+csvSafe(e.sr)+','+csvSafe(e.mn)+','+csvSafe(e.mf)+'\n';}var blob=new Blob([hdr+rows],{type:'text/csv;charset=utf-8;'});var url=URL.createObjectURL(blob);var a=document.createElement('a');a.href=url;a.download='Core365_EventDashboard_Export.csv';a.click();URL.revokeObjectURL(url);}
function csvSafe(s){return '"'+String(s).replace(/"/g,'""')+'"';}
function esc(s){var d=document.createElement('div');d.appendChild(document.createTextNode(String(s)));return d.innerHTML;}
function escJs(s){return String(s).replace(/\\/g,'\\\\').replace(/'/g,"\\'");}
</script>
</body>
</html>
'@

$html = $htmlTemplate.Replace('{{JSON_DATA}}',      $jsonData)
$html = $html.Replace('{{COMPUTER_NAME}}', $pcName)
$html = $html.Replace('{{GEN_TIME}}',      $genTimeStr)
$html = $html.Replace('{{HOURS}}',         [string]$Hours)

$html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

Write-Host ""
Write-Host "  [OK] Dashboard saved to:" -ForegroundColor Green
Write-Host "       $OutputPath" -ForegroundColor White
Write-Host ""

try {
    Start-Process $OutputPath
    Write-Host "  Opening in browser..." -ForegroundColor Cyan
} catch {
    Write-Host "  Could not auto-open. Please open manually." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Done!" -ForegroundColor Green
Write-Host ""