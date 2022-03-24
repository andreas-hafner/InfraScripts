<#
	.SYNOPSIS
		
	.DESCRIPTION
		
	.EXAMPLE  
        
	.INPUTS
		Keine.
	.OUTPUTS
		Keine.
	.NOTES
		Author     : Fabian Niesen
		Filename   : 
		Requires   : PowerShell Version 2.0
		
		Version    : 0.1
		History    : 0.1   FN  26.111.2015  initial version
                    
    .LINK
        
#>
Param(
	[Parameter(Mandatory=$false, Position=1 , ValueFromPipeline=$True)]
	[String]$DOM ="demo.infrastrukturhelden.de",
	[Parameter(Mandatory=$false, Position=2, ValueFromPipeline=$True)]
	[String]$NETBIOS ="DEMO",
	[Parameter(Mandatory=$false, Position=3, ValueFromPipeline=$True)]
	[String]$SMADMINPW ="Chang3M3!",
	[Parameter(Mandatory=$false, Position=4, ValueFromPipeline=$True)]
	[String]$LDAPDOM ="DC=demo,DC=infrastrukturhelden,DC=de",
	[Parameter(Mandatory=$false, Position=5, ValueFromPipeline=$True)]
	[String]$IPSubnet = $null
)


$LogPath= "C:\Install\Scripts\Konfigure-AD"

# End of declaration - do not edit below this Point!

$ErrorActionPreference = "Continue"
$before = Get-Date
$date = get-date -format yyyyMMdd-HHmm
$ErrorLog =$BackupPath+$date+"-error.log"
$WarningLog =$BackupPath+$date+"-warning.log"

If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole( [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
  Write-Warning "You need Admin Permissions to run this script!"| Out-file $ErrorLog -Append
    break
}

  Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
  Import-Module ADDSDeployment
  Write-Verbose "Prepare Managed Service Accounts"
  Add-KdsRootKey -EffectiveImmediately
  
  Write-Verbose "Erstelle Central GPO Store"
  Copy-Item -Path C:\Windows\PolicyDefinitions -Destination C:\Windows\Sysvol\domain\Policies -Recurse

  Write-Verbose "Disable NetBios over TCPIP"
  $nic = Get-WmiObject Win32_NetworkAdapterConfiguration -filter "ipenabled = 'true'"
  $nic.SetTcpipNetbios(2)

  Write-Verbose "Konfiguriere AD-Papierkorb"
  $ADPK = "CN=Recycle Bin Feature,CN=Optional Features,CN=Directory Service,CN=Windows NT,CN=Services,CN=Configuration,"+$LDAPDOM
  Enable-ADOptionalFeature -Identity $ADPK -Scope ForestOrConfigurationSet -Target $DOM -Confirm $false

  Write-Verbose "Vorbereitung für GMSA"
  Add-KdsRootKey -EffectiveImmediately

  Write-Verbose "Erzeuge OU Struktur"
  New-ADOrganizationalUnit -Name Benutzer -Path $LDAPDOM -ProtectedFromAccidentalDeletion $true
  New-ADOrganizationalUnit -Name Computer -Path $LDAPDOM -ProtectedFromAccidentalDeletion $true
  New-ADOrganizationalUnit -Name Server -Path $LDAPDOM -ProtectedFromAccidentalDeletion $true
  New-ADOrganizationalUnit -Name NeueBenutzer -Path $LDAPDOM -ProtectedFromAccidentalDeletion $true
  New-ADOrganizationalUnit -Name NeueComputer -Path $LDAPDOM -ProtectedFromAccidentalDeletion $true
  New-ADOrganizationalUnit -Name Benutzer -Path $("OU=Benutzer,"+$LDAPDOM) -ProtectedFromAccidentalDeletion $true
  New-ADOrganizationalUnit -Name Kontakte -Path $("OU=Benutzer,"+$LDAPDOM) -ProtectedFromAccidentalDeletion $true
  New-ADOrganizationalUnit -Name Gruppen -Path $("OU=Benutzer,"+$LDAPDOM) -ProtectedFromAccidentalDeletion $true
  New-ADOrganizationalUnit -Name Services -Path $LDAPDOM -ProtectedFromAccidentalDeletion $true
  New-ADOrganizationalUnit -Name EXC -Path $("OU=Services,"+$LDAPDOM) -ProtectedFromAccidentalDeletion $true
  New-ADOrganizationalUnit -Name Rechtegruppen -Path $("OU=EXC,OU=Services,"+$LDAPDOM) -ProtectedFromAccidentalDeletion $true
  New-ADOrganizationalUnit -Name Verteilergruppen -Path $("OU=EXC,OU=Services,"+$LDAPDOM) -ProtectedFromAccidentalDeletion $true
  New-ADOrganizationalUnit -Name Server -Path $("OU=EXC,OU=Services,"+$LDAPDOM) -ProtectedFromAccidentalDeletion $true
  New-ADOrganizationalUnit -Name FIL -Path $("OU=Services,"+$LDAPDOM) -ProtectedFromAccidentalDeletion $true
  New-ADOrganizationalUnit -Name Gruppen -Path $("OU=FIL,OU=Services,"+$LDAPDOM) -ProtectedFromAccidentalDeletion $true
  New-ADOrganizationalUnit -Name Server -Path $("OU=FIL,OU=Services,"+$LDAPDOM) -ProtectedFromAccidentalDeletion $true
  New-ADOrganizationalUnit -Name UPD -Path $("OU=Services,"+$LDAPDOM) -ProtectedFromAccidentalDeletion $true
  New-ADOrganizationalUnit -Name Server -Path $("OU=UPD,OU=Services,"+$LDAPDOM) -ProtectedFromAccidentalDeletion $true
  New-ADOrganizationalUnit -Name Server -Path $("OU=Services,"+$LDAPDOM) -ProtectedFromAccidentalDeletion $true

  Write-Verbose "Konfiguriere Umlenkung für neue Computer und Bentzer"
  redirusr $("OU=NeueBenutzer,"+$LDAPDOM)
  redircmp $("OU=NeueComputer,"+$LDAPDOM)
  
  # ADFGPP
  Write-Verbose "Erstelle FineGrained Password Policy"
  New-ADGroup -Name "Dienstekonten" -SamAccountName "Dienstekonten" -groupScope Global -GroupCategory Security -Path $("CN=Users,"+$LDAPDOM) -Description "Securitygroup for DienstekontenPSO"
  New-ADGroup -Name "Adminkonten" -SamAccountName "Adminkonten" -groupScope Global -GroupCategory Security -Path $("CN=Users,"+$LDAPDOM) -Description "Securitygroup for AdminkontenPSO"
  New-ADFineGrainedPasswordPolicy -Name "DienstekontenPSO" -Precedence 200 -ComplexityEnabled $true -Description "Passwortrichtlinie für Dienstekonten" -MaxPasswordAge "90.00:00:00" -MinPasswordAge "1.00:00:00" -MinPasswordLength 16 -PasswordHistoryCount 24
  New-ADFineGrainedPasswordPolicy -Name "AdminkontenPSO" -Precedence 100 -ComplexityEnabled $true -Description "Passwortrichtlinie für Administrative Konten" -MaxPasswordAge "90.00:00:00" -MinPasswordAge "1.00:00:00" -MinPasswordLength 20 -PasswordHistoryCount 24
  Add-ADFineGrainedPasswordPolicySubject DienstekontenPSO -Subjects Dienstekonten
  Add-ADFineGrainedPasswordPolicySubject AdminkontenPSO -Subjects Adminkonten
  
  Write-Verbose "Anlegen der AD Site"
  IF ($IPSubnet -ne $null) { New-ADReplicationSubnet -Name $IPSubnet }
  
$after = Get-Date

$time = $after - $before
$buildTime = "`nBuild finished in ";
if ($time.Minutes -gt 0)
{
    $buildTime += "{0} minute(s) " -f $time.Minutes;
}

$buildTime += "{0} second(s)" -f $time.Seconds;
Write-host "$buildTime" 