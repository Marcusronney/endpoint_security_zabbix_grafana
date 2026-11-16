<#
.SYNOPSIS
  Aplica localmente a linha de base de Microsoft Defender e Firewall do Windows usada na 3F.
.DESCRIPTION
  Use em máquinas fora do domínio, em testes ou em servidores avulsos.
  Em estações do domínio, prefira a GPO (gpo\New-GPO-SegurancaEstacoes.ps1): configurações de GPO
  prevalecem sobre as locais.
  Requer PowerShell como Administrador.
.PARAMETER NetworkProtection
  Enabled (bloqueia) ou AuditMode (só registra). Padrão: AuditMode, para não impactar sistemas legados.
#>
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [ValidateSet('Enabled','AuditMode','Disabled')]
    [string]$NetworkProtection = 'AuditMode',
    [int]$SignatureUpdateIntervalHours = 4
)

$ErrorActionPreference = 'Stop'

$status = Get-MpComputerStatus
if ($status.AMRunningMode -ne 'Normal') {
    Write-Warning ('Defender em modo "{0}". Se houver outro antivírus instalado, o Defender fica passivo e estas configurações não terão efeito.' -f $status.AMRunningMode)
}

$prefs = @{
    DisableRealtimeMonitoring     = $false
    DisableBehaviorMonitoring     = $false
    DisableIOAVProtection         = $false
    DisableScriptScanning         = $false
    MAPSReporting                 = 'Advanced'
    SubmitSamplesConsent          = 'SendSafeSamples'
    CloudBlockLevel               = 'High'
    PUAProtection                 = 'Enabled'
    SignatureUpdateInterval       = $SignatureUpdateIntervalHours
    EnableNetworkProtection       = $NetworkProtection
    ScanScheduleQuickScanTime     = '12:00:00'
    RemediationScheduleDay        = 'Everyday'
}
Set-MpPreference @prefs
Write-Host 'Preferências do Defender aplicadas.'

Update-MpSignature
Write-Host 'Assinaturas atualizadas.'

Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Allow
Write-Host 'Firewall: perfis Domínio, Privado e Público ligados.'

$s = Get-MpComputerStatus
[pscustomobject]@{
    Antivirus           = $s.AntivirusEnabled
    TempoReal           = $s.RealTimeProtectionEnabled
    Comportamento       = $s.BehaviorMonitorEnabled
    IdadeAssinaturaDias = $s.AntivirusSignatureAge
    TamperProtection    = $s.IsTamperProtected
} | Format-List

if (-not $s.IsTamperProtected) {
    Write-Warning 'Tamper Protection desligada: ligue em Segurança do Windows > Proteção contra vírus e ameaças > Gerenciar configurações (não é configurável por GPO).'
}
