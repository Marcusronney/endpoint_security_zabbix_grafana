<#
.SYNOPSIS
  Diagnóstico local: mostra o que o Zabbix lê desta estação (Defender, Firewall, agente).
.DESCRIPTION
  Consulta as mesmas classes WMI usadas pelo template "Windows – Estação de Trabalho (3F)":
    root\Microsoft\Windows\Defender  -> MSFT_MpComputerStatus, MSFT_MpThreatDetection
    root\StandardCimv2               -> MSFT_NetFirewallProfile
  e verifica serviço, porta e regra de firewall do Zabbix Agent 2.
  Execute como Administrador para resultado completo.
#>
[CmdletBinding()]
param([int]$SigMaxAgeDays = 5)

function Show-Check([string]$Name, [bool]$Ok, [string]$Detail) {
    $mark = if ($Ok) { '[ OK ]' } else { '[FALHA]' }
    $color = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ('{0} {1,-38} {2}' -f $mark, $Name, $Detail) -ForegroundColor $color
}

Write-Host ''
Write-Host ('=== {0} - {1:dd/MM/yyyy HH:mm} ===' -f $env:COMPUTERNAME, (Get-Date)) -ForegroundColor Cyan

try {
    $mp = Get-CimInstance -Namespace 'root\Microsoft\Windows\Defender' -ClassName 'MSFT_MpComputerStatus' -ErrorAction Stop
    Show-Check 'Serviço do Defender'            ([bool]$mp.AMServiceEnabled)          ''
    Show-Check 'Antivírus ligado'               ([bool]$mp.AntivirusEnabled)          ''
    Show-Check 'Proteção em tempo real'         ([bool]$mp.RealTimeProtectionEnabled) ''
    Show-Check 'Monitor de comportamento'       ([bool]$mp.BehaviorMonitorEnabled)    ''
    Show-Check 'Modo de execução Normal'        ($mp.AMRunningMode -eq 'Normal')      ([string]$mp.AMRunningMode)
    Show-Check 'Assinatura em dia'              ($mp.AntivirusSignatureAge -le $SigMaxAgeDays) ('{0} dia(s)' -f $mp.AntivirusSignatureAge)
    Show-Check 'Verificação rápida recente'     ($mp.QuickScanAge -le 7)               ('{0} dia(s)' -f $mp.QuickScanAge)
    $full = if ($mp.FullScanAge -ge 4294967295) { 'nunca' } else { '{0} dia(s)' -f $mp.FullScanAge }
    Show-Check 'Verificação completa executada' ($mp.FullScanAge -lt 4294967295)      $full
    Show-Check 'Tamper Protection'              ([bool]$mp.IsTamperProtected)         ''
} catch {
    Show-Check 'WMI do Defender' $false $_.Exception.Message
}

try {
    $det = @(Get-CimInstance -Namespace 'root\Microsoft\Windows\Defender' -ClassName 'MSFT_MpThreatDetection' -ErrorAction Stop)
    $recent = @($det | Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddDays(-7) })
    Show-Check 'Detecções nos últimos 7 dias' ($recent.Count -eq 0) ([string]$recent.Count)
    $active = @(Get-MpThreat -ErrorAction SilentlyContinue | Where-Object { $_.IsActive })
    Show-Check 'Ameaças ativas' ($active.Count -eq 0) (($active | ForEach-Object { $_.ThreatName }) -join ', ')
} catch {
    Show-Check 'Histórico de ameaças' $false $_.Exception.Message
}

try {
    $fw = Get-CimInstance -Namespace 'root\StandardCimv2' -ClassName 'MSFT_NetFirewallProfile' -ErrorAction Stop
    foreach ($p in $fw) { Show-Check ('Firewall perfil {0}' -f $p.Name) ($p.Enabled -eq 1) '' }
} catch {
    Show-Check 'WMI do Firewall' $false $_.Exception.Message
}

$svc = Get-Service -Name 'Zabbix Agent 2' -ErrorAction SilentlyContinue
Show-Check 'Serviço Zabbix Agent 2' ($svc -and $svc.Status -eq 'Running') ([string]$svc.Status)
$listen = Get-NetTCPConnection -LocalPort 10050 -State Listen -ErrorAction SilentlyContinue
Show-Check 'Porta 10050 escutando' ([bool]$listen) ''
$rule = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'Zabbix Agent*' -and $_.Enabled -eq 'True' }
Show-Check 'Regra de firewall do Zabbix' ([bool]$rule) (($rule | Select-Object -ExpandProperty DisplayName) -join '; ')

$conf = Join-Path $env:ProgramFiles 'Zabbix Agent 2\zabbix_agent2.conf'
if (Test-Path $conf) {
    Write-Host ''
    Write-Host 'Configuração do agente:' -ForegroundColor Cyan
    Get-Content $conf | Where-Object { $_ -match '^(Server|ServerActive|Hostname|HostMetadata|Timeout)=' } | ForEach-Object { Write-Host ('  ' + $_) }
}
Write-Host ''
