# GPOs do projeto Segurança das Estações

## GPO 1 – "SEG - Estacoes - Defender e Firewall"

A Gpo é criada pelo script gpo/New-GPO-SegurancaEstacoes.ps1. Tudo em *Computer Configuration* (configurações de usuário desativadas).

### Microsoft Defender Antivírus
*Computer Configuration → Policies → Administrative Templates → Windows Components → Microsoft Defender Antivirus*

| Configuração (GPMC) | Registro | Valor |
|:--|:--|:--|
| Real-time Protection → Turn off real-time protection | Real-Time Protection\DisableRealtimeMonitoring | 0 (Disabled = proteção ligada) |
| Real-time Protection → Turn on behavior monitoring | Real-Time Protection\DisableBehaviorMonitoring | 0 |
| Real-time Protection → Scan all downloaded files and attachments | Real-Time Protection\DisableIOAVProtection | 0 |
| Real-time Protection → Turn on script scanning | Real-Time Protection\DisableScriptScanning | 0 |
| MAPS → Join Microsoft MAPS | Spynet\SpynetReporting | 2 (Advanced) |
| MAPS → Send file samples when further analysis is required | Spynet\SubmitSamplesConsent | 1 (safe samples) |
| MpEngine → Select cloud protection level | MpEngine\MpCloudBlockLevel | 2 (High) |
| Configure detection for potentially unwanted applications | PUAProtection | 1 (Block) |
| Security Intelligence Updates → Specify the interval to check for updates | Signature Updates\SignatureUpdateInterval | 4 (horas) |
| Scan → Specify the time for a daily quick scan | Scan\ScheduleQuickScanTime | 720 (12:00) |
| Scan → Specify the scan type to use for a scheduled scan | Scan\ScanParameters | 2 (Full) |
| Scan → Specify the day of the week to run a scheduled scan | Scan\ScheduleDay | 7 (sábado) |
| Scan → Specify the time of day to run a scheduled scan | Scan\ScheduleTime | 720 (12:00) |

Chave base: HKLM\SOFTWARE\Policies\Microsoft\Windows Defender

### Firewall do Windows
*Computer Configuration → Policies → Administrative Templates → Network → Network Connections → Windows Defender Firewall*
(equivalente em registro, HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\{DomainProfile|StandardProfile|PublicProfile})

| Valor | Configuração |
|:--|:--|
| EnableFirewall = 1 | Firewall ligado nos 3 perfis |
| DefaultInboundAction = 1 | Entrada bloqueada por padrão |
| DefaultOutboundAction = 0 | Saída permitida |

Regras (*Windows Settings → Security Settings → Windows Defender Firewall with Advanced Security → Inbound Rules*):

| Regra | Protocolo/porta | Origem | Perfil |
|:--|:--|:--|:--|
| Zabbix Agent 2 (TCP 10050) - servidor Zabbix | TCP 10050 | 192.168.0.40 | Domínio |
| Zabbix - ICMP Echo do servidor Zabbix | ICMPv4 tipo 8 | 192.168.0.40 | Domínio |

> Atenção: com DefaultInboundAction = 1 e regras locais mescladas (padrão), aplicações que já tinham regra local
> continuam funcionando. Se a sua política desativar a mesclagem de regras locais, revise antes as exceções
> necessárias (compartilhamento de arquivos, acesso remoto etc.).

## GPO 2 – "SEG - Estacoes - Zabbix Agent"

*Computer Configuration → Policies → Windows Settings → Scripts (Startup/Shutdown) → Startup → PowerShell Scripts*

| Campo | Valor |
|:--|:--|
| Script | \\f3f.local\NETLOGON\Zabbix\Install-ZabbixAgent2.ps1 |
| Parâmetros | -MsiPath "\\f3f.local\NETLOGON\Zabbix\zabbix_agent2-7.4.2-windows-amd64-openssl.msi" -ZabbixServer 192.168.0.40 |

Recomendado também:
*Computer Configuration → Policies → Administrative Templates → System → Logon → Always wait for the network at
computer startup and logon* = Enabled (garante acesso ao compartilhamento no boot).

O script é idempotente: roda a cada inicialização, instala só se faltar e corrige a configuração se alguém alterar.

## Ordem de aplicação

1. Criar as duas GPOs.
2. Vincular a uma OU piloto (5–10 estações) e validar com Test-DefenderZabbix.ps1 + painel do Grafana.
3. Vincular às OUs de estações em ondas.

## Limitações

- **Tamper Protection** não pode ser imposta por GPO (só Intune/portal Microsoft Defender). O template do Zabbix
  alerta quando está desligada.
- Se houver outro antivírus instalado, o Defender entra em modo passivo e as políticas acima não protegem a máquina;
  o painel mostra o modo de execução (ws.def[mode]).
