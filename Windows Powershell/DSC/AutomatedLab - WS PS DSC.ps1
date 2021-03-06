﻿<#
This Sample Code is provided for the purpose of illustration only
and is not intended to be used in a production environment.  THIS
SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT
WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT
LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS
FOR A PARTICULAR PURPOSE.  We grant You a nonexclusive, royalty-free
right to use and modify the Sample Code and to reproduce and distribute
the object code form of the Sample Code, provided that You agree:
(i) to not use Our name, logo, or trademarks to market Your software
product in which the Sample Code is embedded; (ii) to include a valid
copyright notice on Your software product in which the Sample Code is
embedded; and (iii) to indemnify, hold harmless, and defend Us and
Our suppliers from and against any claims or lawsuits, including
attorneys' fees, that arise or result from the use or distribution
of the Sample Code.
#>
#requires -Version 5 -Modules AutomatedLab -RunAsAdministrator 
trap {
    Write-Host "Stopping Transcript ..."
    Stop-Transcript
    Send-ALNotification -Activity 'Lab started' -Message ('Lab deployment failed !') -Provider (Get-LabConfigurationItem -Name Notifications.SubscribedProviders)
} 
Clear-Host
$PreviousVerbosePreference = $VerbosePreference
$VerbosePreference = 'SilentlyContinue'
$PreviousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
$CurrentScript = $MyInvocation.MyCommand.Path
#Getting the current directory (where this script file resides)
$CurrentDir = Split-Path -Path $CurrentScript -Parent
$TranscriptFile = $CurrentScript -replace ".ps1$", "_$("{0:yyyyMMddHHmmss}" -f (Get-Date)).txt"
Start-Transcript -Path $TranscriptFile -IncludeInvocationHeader

#region Global variables definition
$Now = Get-Date
$10YearsFrom = $Now.AddYears(10)
$CertValidityPeriod = New-TimeSpan -Start $Now -End $10YearsFrom
$Logon = 'Administrator'
#$ClearTextPassword = 'PowerShell5!'
$ClearTextPassword = 'P@ssw0rd'
$SecurePassword = ConvertTo-SecureString -String $ClearTextPassword -AsPlainText -Force
$NetBiosDomainName = 'CONTOSO'
$FQDNDomainName = 'contoso.com'
$LabFilesZipPath = Join-Path -Path $CurrentDir -ChildPath "LabFiles.zip"
$DemoFilesZipPath = Join-Path -Path $CurrentDir -ChildPath "Demos.zip"
$StandardUser = 'ericlang'

$NetworkID = '10.0.0.0/16' 
$DCIPv4Address = '10.0.0.1'
$PULLIPv4Address = '10.0.0.11'
$MS1IPv4Address = '10.0.0.101'
$MS2IPv4Address = '10.0.0.102'

$LabName = 'IISWSPSDSC'
#endregion

#Cleaning previously existing lab
if ($LabName -in (Get-Lab -List)) {
    Remove-Lab -Name $LabName -Confirm:$false -ErrorAction SilentlyContinue
}

#create an empty lab template and define where the lab XML files and the VMs will be stored
New-LabDefinition -Name $LabName -DefaultVirtualizationEngine HyperV

#make the network definition
Add-LabVirtualNetworkDefinition -Name $LabName -HyperVProperties @{
    SwitchType = 'Internal'
} -AddressSpace $NetworkID
Add-LabVirtualNetworkDefinition -Name 'Default Switch' -HyperVProperties @{ SwitchType = 'External'; AdapterName = 'Wi-Fi' }


#and the domain definition with the domain admin account
Add-LabDomainDefinition -Name $FQDNDomainName -AdminUser $Logon -AdminPassword $ClearTextPassword

#these credentials are used for connecting to the machines. As this is a lab we use clear-text passwords
Set-LabInstallationCredential -Username $Logon -Password $ClearTextPassword

#defining default parameter values, as these ones are the same for all the machines
$PSDefaultParameterValues = @{
    'Add-LabMachineDefinition:Network'         = $LabName
    'Add-LabMachineDefinition:DomainName'      = $FQDNDomainName
    'Add-LabMachineDefinition:MinMemory'       = 1GB
    'Add-LabMachineDefinition:MaxMemory'       = 2GB
    'Add-LabMachineDefinition:Memory'          = 2GB
    'Add-LabMachineDefinition:OperatingSystem' = 'Windows Server 2019 Standard (Desktop Experience)'
    #'Add-LabMachineDefinition:Processors'      = 4
}


$DCNetAdapter = @()
$DCNetAdapter += New-LabNetworkAdapterDefinition -VirtualSwitch $LabName -Ipv4Address $DCIPv4Address
#Adding an Internet Connection on the DC (Required for the SQL Setup via AutomatedLab)
$DCNetAdapter += New-LabNetworkAdapterDefinition -VirtualSwitch 'Default Switch' -UseDhcp

$PULLNetAdapter = @()
$PULLNetAdapter += New-LabNetworkAdapterDefinition -VirtualSwitch $LabName -Ipv4Address $PULLIPv4Address
#Adding an Internet Connection on the DC (Required for the SQL Setup via AutomatedLab)
$PULLNetAdapter += New-LabNetworkAdapterDefinition -VirtualSwitch 'Default Switch' -UseDhcp

#region server definitions
#Domain controller + Certificate Authority
Add-LabMachineDefinition -Name DC -Roles RootDC, CARoot -NetworkAdapter $DCNetAdapter
#SQL Server
Add-LabMachineDefinition -Name PULL -NetworkAdapter $PULLNetAdapter
#IIS front-end server
Add-LabMachineDefinition -Name MS1 -IpAddress $MS1IPv4Address
#IIS front-end server
Add-LabMachineDefinition -Name MS2 -IpAddress $MS2IPv4Address
#endregion

#Installing servers
Install-Lab
Checkpoint-LabVM -SnapshotName FreshInstall -All -Verbose

#region Installing Required Windows Features
$machines = Get-LabVM
Install-LabWindowsFeature -FeatureName Telnet-Client -ComputerName $machines -IncludeManagementTools
#endregion

Invoke-LabCommand -ActivityName "Disabling IE ESC" -ComputerName $machines -ScriptBlock {
    #Disabling IE ESC
    $AdminKey = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}'
    $UserKey = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}'
    Set-ItemProperty -Path $AdminKey -Name 'IsInstalled' -Value 0 -Force
    Set-ItemProperty -Path $UserKey -Name 'IsInstalled' -Value 0 -Force
    Rundll32 iesetup.dll, IEHardenLMSettings
    Rundll32 iesetup.dll, IEHardenUser
    Rundll32 iesetup.dll, IEHardenAdmin
    Remove-Item -Path $AdminKey -Force
    Remove-Item -Path $UserKey -Force

    #Renaming the main NIC adapter to Corp (used in the Security lab)
    Rename-NetAdapter -Name "$using:labName 0" -NewName 'Corp' -PassThru -ErrorAction SilentlyContinue
    Rename-NetAdapter -Name "Ethernet" -NewName 'Corp' -PassThru -ErrorAction SilentlyContinue
    Rename-NetAdapter -Name "Default Switch 0" -NewName 'Internet' -PassThru -ErrorAction SilentlyContinue
}

#Installing and setting up DNS
Invoke-LabCommand -ActivityName 'DNS, AD & CA Setup on DC' -ComputerName DC -ScriptBlock {
    #region DNS management
    #Reverse lookup zone creation
    Add-DnsServerPrimaryZone -NetworkID $using:NetworkID -ReplicationScope 'Forest' 

    #Creating AD Users
    New-ADUser -Name $Using:StandardUser -AccountPassword $using:SecurePassword -PasswordNeverExpires $true -CannotChangePassword $True -Enabled $true

    #Installing the ADCSTemplateForPSEncryption for creating a Document Encryption template (Internet connection required)
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Install-Module -Name ADCSTemplateForPSEncryption -Force

    Import-Module -Name ADCSTemplateForPSEncryption -Force
    #Creating the Document Encryption template
    New-ADCSTemplateForPSEncryption -DisplayName DocumentEncryption -Server ([System.Net.Dns]::GetHostByName($env:computerName)).Hostname -GroupName "Domain Computers", "Domain Controllers" -AutoEnroll #-Publish
}

#region Certification Authority : Creation and SSL Certificate Generation
#Get the CA
$CertificationAuthority = Get-LabIssuingCA
#Generating a new template for 10-year SSL Web Server certificate
New-LabCATemplate -TemplateName WebServer10Years -DisplayName 'WebServer10Years' -SourceTemplateName WebServer -ApplicationPolicy 'Server Authentication' -EnrollmentFlags Autoenrollment -PrivateKeyFlags AllowKeyExport -Version 2 -SamAccountName 'Domain Computers' -ValidityPeriod $CertValidityPeriod -ComputerName $CertificationAuthority -ErrorAction Stop
#Generating a new template for 10-year document encryption certificate
New-LabCATemplate -TemplateName DocumentEncryption10Years -DisplayName 'DocumentEncryption10Years' -SourceTemplateName DocumentEncryption -ApplicationPolicy 'Document Encryption' -EnrollmentFlags Autoenrollment -PrivateKeyFlags AllowKeyExport -Version 2 -SamAccountName 'Domain Computers' -ValidityPeriod $CertValidityPeriod -ComputerName $CertificationAuthority -ErrorAction Stop

$PULLWebSiteSSLCert = Request-LabCertificate -Subject "CN=pull.contoso.com" -SAN "pull", "pull.contoso.com" -TemplateName WebServer10Years -ComputerName PULL -PassThru -ErrorAction Stop

Invoke-LabCommand -ActivityName 'Requesting Document Encryption Certificate & Disabling Windows Update service' -ComputerName $machines -ScriptBlock {
    $DocumentEncryption10YearsCert = Get-Certificate -Template DocumentEncryption10Years -Url 'ldap:' -CertStoreLocation 'Cert:\LocalMachine\My'
    Stop-Service WUAUSERV -PassThru | Set-Service -StartupType Disabled
    
    New-Item -Path \\pull\c$\PublicKeys\ -ItemType Directory -Force
    Export-Certificate -Cert $DocumentEncryption10YearsCert.Certificate -FilePath "\\pull\c$\PublicKeys\$env:COMPUTERNAME.cer" -Force
} 


Invoke-LabCommand -ActivityName 'Generating CSV file for listing certificate data' -ComputerName PULL -ScriptBlock {
    $PublicKeysFolder = "C:\PublicKeys"
    $CSVFile = Join-Path -Path $PublicKeysFolder -ChildPath "index.csv"
    $CertificateFiles = Get-ChildItem -Path $PublicKeysFolder -Filter *.cer -File
    $CSVData = $CertificateFiles | ForEach-Object -Process {
        $Path=$_.FullName
        $CurrentCertificate = Get-PfxCertificate $Path
        if ($CurrentCertificate.Subject -match "CN=(?<NETBIOS>\w*)\.(.*)+$")
        {
            $Node=$Matches["NETBIOS"]
        }
        else
        {
            $Node=$_.BaseName
        }
        $Thumbprint = $CurrentCertificate.Thumbprint
        $GUID = (New-Guid).Guid
        [PSCustomObject]@{Node=$Node;Path=$Path;Thumbprint=$Thumbprint;GUID=$GUID}
    }
    $CSVData | Export-Csv -Path $CSVFile -NoTypeInformation -Encoding UTF8
} 


#Removing the Internet Connection on the DC (Required only for installing the ADCSTemplateForPSEncryption PowerShell module)
Get-VM -Name 'DC' | Remove-VMNetworkAdapter -Name 'Default Switch' -ErrorAction SilentlyContinue

Checkpoint-LabVM -SnapshotName 'FullInstall' -All

Show-LabDeploymentSummary -Detailed

$VerbosePreference = $PreviousVerbosePreference
$ErrorActionPreference = $PreviousErrorActionPreference
#Restore-LabVMSnapshot -SnapshotName 'FullInstall' -All -Verbose

Stop-Transcript