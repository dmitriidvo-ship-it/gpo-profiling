
param(
    [string]$DcIP      = "192.168.10.1",
    [string]$SysvolPath = "\\192.168.10.1\sysvol",
    [int]   $NRuns     = 30
)

$ResultsFile = "results_windows_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$Results = @()

Write-Host "DC_IP=$DcIP | SYSVOL=$SysvolPath | N=$NRuns"
Write-Host "Результаты → $ResultsFile"
Write-Host ""

# Убедиться, что журнал GroupPolicy/Operational включён
$logName = "Microsoft-Windows-GroupPolicy/Operational"
$log = Get-WinEvent -ListLog $logName -ErrorAction SilentlyContinue
if ($log -and -not $log.IsEnabled) {
    Write-Warning "Журнал $logName отключён. Включаю..."
    $log.IsEnabled = $true
    $log.SaveChanges()
}

for ($i = 1; $i -le $NRuns; $i++) {


    $ldapStart = Get-Date
    $null = Test-NetConnection -ComputerName $DcIP -Port 389 -WarningAction SilentlyContinue
    $ldapEnd = Get-Date
    $T_LDAP = [math]::Round(($ldapEnd - $ldapStart).TotalMilliseconds)


    $sysvolStart = Get-Date
    $null = Get-ChildItem -Path $SysvolPath -ErrorAction SilentlyContinue
    $sysvolEnd = Get-Date
    $T_SYSVOL = [math]::Round(($sysvolEnd - $sysvolStart).TotalMilliseconds)



    $beforeUpdate = Get-Date

    $totalStart = Get-Date
    gpupdate /force | Out-Null
    $totalEnd = Get-Date
    $T_total = [math]::Round(($totalEnd - $totalStart).TotalMilliseconds)


    Start-Sleep -Milliseconds 500  # дать журналу записать события

    $cseEvents = Get-WinEvent -LogName $logName -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -eq 5016 -and $_.TimeCreated -ge $beforeUpdate }

    $T_CSE_total = 0
    $cseDetails  = @()

    foreach ($evt in $cseEvents) {
        $xml = [xml]$evt.ToXml()
        $ns  = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $ns.AddNamespace("e", "http://schemas.microsoft.com/win/2004/08/events/event")

        # DurationInSeconds хранится в EventData
        $durationNode = $xml.SelectSingleNode(
            "//e:Data[@Name='DurationInSeconds']", $ns)
        if ($durationNode) {
            $durationMs = [math]::Round([double]$durationNode.'#text' * 1000)
            $cseNameNode = $xml.SelectSingleNode(
                "//e:Data[@Name='CSEExtensionName']", $ns)
            $cseName = if ($cseNameNode) { $cseNameNode.'#text' } else { "Unknown" }
            $T_CSE_total += $durationMs
            $cseDetails  += "${cseName}=${durationMs}ms"
        }
    }

    $cseString = if ($cseDetails.Count -gt 0) { $cseDetails -join ";" } else { "n/a" }

    Write-Host ("run {0,2}: total={1}ms  LDAP={2}ms  SYSVOL={3}ms  CSE_sum={4}ms  [{5}]" `
        -f $i, $T_total, $T_LDAP, $T_SYSVOL, $T_CSE_total, $cseString)

    $Results += [PSCustomObject]@{
        run        = $i
        T_total_ms = $T_total
        T_LDAP_ms  = $T_LDAP
        T_SYSVOL_ms= $T_SYSVOL
        T_CSE_ms   = $T_CSE_total
        CSE_details= $cseString
    }

    Start-Sleep -Seconds 2
}

$Results | Export-Csv -Path $ResultsFile -NoTypeInformation -Encoding UTF8
Write-Host ""
Write-Host "=== Готово. Результаты сохранены в $ResultsFile ==="
Write-Host "Первый замер (run=1) рекомендуется исключить как 'холодный старт'."
