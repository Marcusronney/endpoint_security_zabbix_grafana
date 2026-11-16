<#
.SYNOPSIS
  Correção rápida de uma estação apontada no painel (antivírus/tempo real desligado, assinatura velha, ameaça ativa).
.DESCRIPTION
  1. Religa proteção em tempo real, comportamento e IOAV (se não houver GPO dizendo o contrário).
  2. Atualiza as assinaturas.
  3. Remove ameaças ativas conhecidas (ação padrão do Defender).
  4. Executa verificação rápida (ou completa com -FullScan).
  Pode ser executado localmente ou remotamente:
    Invoke-Command -ComputerName N3F141 -FilePath .\Invoke-DefenderRemediacao.ps1
#>
#Requires -RunAsAdministrator
[CmdletBinding()]
param([switch]$FullScan)

$ErrorActionPreference = 'Continue'

Write-Host '1/4 Religando proteções...'
Set-MpPreference -DisableRealtimeMonitoring $false -DisableBehaviorMonitoring $false -DisableIOAVProtection $false

Write-Host '2/4 Atualizando assinaturas...'
Update-MpSignature

Write-Host '3/4 Tratando ameaças ativas...'
$active = @(Get-MpThreat -ErrorAction SilentlyContinue | Where-Object { $_.IsActive })
if ($active.Count -gt 0) {
    $active | ForEach-Object { Write-Host ('   - {0}' -f $_.ThreatName) }
    Remove-MpThreat
} else {
    Write-Host '   nenhuma ameaça ativa.'
}

$type = if ($FullScan) { 'FullScan' } else { 'QuickScan' }
Write-Host ('4/4 Executando {0} (pode demorar)...' -f $type)
Start-MpScan -ScanType $type

$s = Get-MpComputerStatus
[pscustomobject]@{
    Estacao             = $env:COMPUTERNAME
    Antivirus           = $s.AntivirusEnabled
    TempoReal           = $s.RealTimeProtectionEnabled
    IdadeAssinaturaDias = $s.AntivirusSignatureAge
    AmeacasAtivas       = @(Get-MpThreat -ErrorAction SilentlyContinue | Where-Object { $_.IsActive }).Count
} | Format-List
Write-Host 'O Zabbix reflete o novo estado na próxima coleta (até 15 min).'
