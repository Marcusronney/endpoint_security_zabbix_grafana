<#
.SYNOPSIS
  Cria (ou atualiza) a GPO "SEG - Estacoes - Defender e Firewall" da 3F.
.DESCRIPTION
  Configurações de computador:
   - Microsoft Defender Antivírus: tempo real, comportamento, IOAV e verificação de scripts ligados;
     MAPS avançado; envio de amostras seguras; bloqueio na nuvem Alto; PUA bloqueado;
     atualização de assinatura a cada 4 h; verificação rápida diária 12:00; verificação completa semanal (sábado 12:00).
   - Firewall do Windows: perfis Domínio, Privado e Público ligados; entrada bloqueada por padrão; saída liberada.
   - Regra de entrada TCP 10050 somente do servidor Zabbix (perfil Domínio).
  Requer RSAT (módulos GroupPolicy e NetSecurity) e permissão de administrador de domínio.
.EXAMPLE
  .\New-GPO-SegurancaEstacoes.ps1 -TargetOU 'OU=Piloto,OU=Estacoes,DC=f3f,DC=local' -Link
#>
[CmdletBinding()]
param(
    [string]$GpoName      = 'SEG - Estacoes - Defender e Firewall',
    [string]$TargetOU     = '',
    [string]$ZabbixServer = '192.168.0.40',
    [switch]$Link
)

$ErrorActionPreference = 'Stop'
Import-Module GroupPolicy
Import-Module NetSecurity

$domain = (Get-ADDomain -ErrorAction SilentlyContinue).DNSRoot
if (-not $domain) { $domain = $env:USERDNSDOMAIN }

$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
if (-not $gpo) {
    $gpo = New-GPO -Name $GpoName -Comment 'Linha de base Defender + Firewall + porta do Zabbix Agent (projeto Segurança das Estações).'
    Write-Host ('GPO criada: {0}' -f $GpoName)
} else {
    Write-Host ('GPO existente, atualizando: {0}' -f $GpoName)
}
# Configurações de usuário não são usadas
$gpo.GpoStatus = 'UserSettingsDisabled'

function Set-Pol([string]$Key, [string]$Name, [int]$Value) {
    Set-GPRegistryValue -Name $GpoName -Key $Key -ValueName $Name -Type DWord -Value $Value | Out-Null
    Write-Host ('  {0}\{1} = {2}' -f $Key, $Name, $Value)
}

$def = 'HKLM\SOFTWARE\Policies\Microsoft\Windows Defender'
Write-Host 'Microsoft Defender Antivírus:'
Set-Pol "$def\Real-Time Protection" 'DisableRealtimeMonitoring'  0
Set-Pol "$def\Real-Time Protection" 'DisableBehaviorMonitoring'  0
Set-Pol "$def\Real-Time Protection" 'DisableIOAVProtection'      0
Set-Pol "$def\Real-Time Protection" 'DisableScriptScanning'      0
Set-Pol "$def\Spynet"               'SpynetReporting'            2   # MAPS avançado
Set-Pol "$def\Spynet"               'SubmitSamplesConsent'       1   # enviar amostras seguras
Set-Pol "$def\MpEngine"             'MpCloudBlockLevel'          2   # Alto
Set-Pol "$def"                      'PUAProtection'              1   # bloquear aplicativos potencialmente indesejados
Set-Pol "$def\Signature Updates"    'SignatureUpdateInterval'    4   # horas
Set-Pol "$def\Scan"                 'ScheduleQuickScanTime'      720 # 12:00 (minutos após 0h), diária
Set-Pol "$def\Scan"                 'ScanParameters'             2   # verificação agendada = completa
Set-Pol "$def\Scan"                 'ScheduleDay'                7   # sábado (0=todo dia, 1=domingo ... 7=sábado)
Set-Pol "$def\Scan"                 'ScheduleTime'               720 # 12:00

$fw = 'HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall'
Write-Host 'Firewall do Windows:'
foreach ($p in 'DomainProfile', 'StandardProfile', 'PublicProfile') {
    Set-Pol "$fw\$p" 'EnableFirewall'        1
    Set-Pol "$fw\$p" 'DefaultInboundAction'  1  # bloquear
    Set-Pol "$fw\$p" 'DefaultOutboundAction' 0  # permitir
}

Write-Host 'Regra de entrada do Zabbix Agent:'
$store = '{0}\{1}' -f $domain, $GpoName
$ruleName = 'Zabbix Agent 2 (TCP 10050) - servidor Zabbix'
$existing = Get-NetFirewallRule -PolicyStore $store -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $ruleName }
if (-not $existing) {
    New-NetFirewallRule -PolicyStore $store -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort 10050 -RemoteAddress $ZabbixServer -Action Allow -Profile Domain | Out-Null
    Write-Host ('  criada: {0} (origem {1})' -f $ruleName, $ZabbixServer)
} else {
    Write-Host '  já existe.'
}
$icmpName = 'Zabbix - ICMP Echo do servidor Zabbix'
if (-not (Get-NetFirewallRule -PolicyStore $store -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $icmpName })) {
    New-NetFirewallRule -PolicyStore $store -DisplayName $icmpName -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -RemoteAddress $ZabbixServer -Action Allow -Profile Domain | Out-Null
    Write-Host ('  criada: {0}' -f $icmpName)
}

if ($Link) {
    if (-not $TargetOU) { throw 'Informe -TargetOU para vincular a GPO.' }
    $links = (Get-GPInheritance -Target $TargetOU).GpoLinks | Where-Object { $_.DisplayName -eq $GpoName }
    if (-not $links) {
        New-GPLink -Name $GpoName -Target $TargetOU -LinkEnabled Yes | Out-Null
        Write-Host ('GPO vinculada a {0}' -f $TargetOU)
    } else {
        Write-Host ('GPO já vinculada a {0}' -f $TargetOU)
    }
}

Write-Host ''
Write-Host 'Concluído. Nas estações: gpupdate /force e conferir com scripts\powershell\Test-DefenderZabbix.ps1'
Write-Host 'Observação: Tamper Protection não é configurável por GPO; o Zabbix apenas monitora e alerta.'
