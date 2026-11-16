<#
.SYNOPSIS
  Instala e configura o Zabbix Agent 2 em estações Windows da 3F (idempotente).
.DESCRIPTION
  Pensado para rodar como script de INICIALIZAÇÃO de computador via GPO (conta SYSTEM).
  - Se o agente não existir: instala o MSI em modo silencioso.
  - Garante Server, ServerActive, Hostname (FQDN), HostMetadata e Timeout no arquivo de configuração.
  - Garante regra de firewall de entrada TCP 10050 somente a partir do servidor Zabbix.
  - Garante o serviço em execução e com inicialização automática.
  Log: C:\Windows\Temp\zabbix-agent2-install.log
.EXAMPLE
  .\Install-ZabbixAgent2.ps1 -MsiPath '\\f3f.local\NETLOGON\Zabbix\zabbix_agent2-7.4.2-windows-amd64-openssl.msi' -ZabbixServer 192.168.0.40
#>
[CmdletBinding()]
param(
    [string]$MsiPath      = '\\f3f.local\NETLOGON\Zabbix\zabbix_agent2-7.4.2-windows-amd64-openssl.msi',
    [string]$ZabbixServer = '192.168.0.40',
    [string]$HostMetadata = 'Windows-Estacao-3F',
    [int]$Timeout         = 10
)

$ErrorActionPreference = 'Stop'
$LogFile     = 'C:\Windows\Temp\zabbix-agent2-install.log'
$ServiceName = 'Zabbix Agent 2'
$ConfPath    = Join-Path $env:ProgramFiles 'Zabbix Agent 2\zabbix_agent2.conf'

function Write-Log([string]$Message) {
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Set-ConfValue([string]$Path, [string]$Key, [string]$Value) {
    $content = @(Get-Content -Path $Path -Encoding UTF8)
    $pattern = '^\s*#?\s*' + [regex]::Escape($Key) + '\s*='
    $found = $false
    $new = foreach ($l in $content) {
        if (-not $found -and $l -match $pattern) { $found = $true; '{0}={1}' -f $Key, $Value }
        elseif ($found -and $l -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) { continue }
        else { $l }
    }
    if (-not $found) { $new += ('{0}={1}' -f $Key, $Value) }
    Set-Content -Path $Path -Value $new -Encoding UTF8
}

try {
    $fqdn = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName
    Write-Log ('Início. Estação: {0}' -f $fqdn)

    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        if (-not (Test-Path -Path $MsiPath)) { throw ('MSI não encontrado: {0}' -f $MsiPath) }
        $msiArgs = @(
            '/i', ('"{0}"' -f $MsiPath),
            '/qn', '/norestart',
            '/l*v', ('"{0}"' -f ($LogFile + '.msi.txt')),
            ('SERVER={0}' -f $ZabbixServer),
            ('SERVERACTIVE={0}' -f $ZabbixServer),
            ('HOSTNAME={0}' -f $fqdn),
            'ENABLEPATH=1'
        )
        Write-Log 'Instalando Zabbix Agent 2...'
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
        if ($p.ExitCode -notin 0, 3010) { throw ('msiexec retornou {0}' -f $p.ExitCode) }
        Write-Log 'Instalação concluída.'
    } else {
        Write-Log 'Agente já instalado; validando configuração.'
    }

    if (-not (Test-Path -Path $ConfPath)) { throw ('Arquivo de configuração não encontrado: {0}' -f $ConfPath) }
    $before = Get-FileHash -Path $ConfPath
    Set-ConfValue $ConfPath 'Server'       $ZabbixServer
    Set-ConfValue $ConfPath 'ServerActive' $ZabbixServer
    Set-ConfValue $ConfPath 'Hostname'     $fqdn
    Set-ConfValue $ConfPath 'HostMetadata' $HostMetadata
    Set-ConfValue $ConfPath 'Timeout'      ([string]$Timeout)
    $changed = (Get-FileHash -Path $ConfPath).Hash -ne $before.Hash

    $ruleName = 'Zabbix Agent 2 (TCP 10050) - servidor Zabbix'
    if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort 10050 -RemoteAddress $ZabbixServer -Action Allow -Profile Domain,Private | Out-Null
        Write-Log 'Regra de firewall criada.'
    }

    Set-Service -Name $ServiceName -StartupType Automatic
    $svc = Get-Service -Name $ServiceName
    if ($changed -and $svc.Status -eq 'Running') { Restart-Service -Name $ServiceName -Force; Write-Log 'Serviço reiniciado (configuração alterada).' }
    elseif ($svc.Status -ne 'Running') { Start-Service -Name $ServiceName; Write-Log 'Serviço iniciado.' }

    Write-Log 'Fim: OK.'
    exit 0
}
catch {
    Write-Log ('ERRO: {0}' -f $_.Exception.Message)
    exit 1
}
