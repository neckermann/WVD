# Microsoft Windows Virutal Desktop Tenant Setup
# https://docs.microsoft.com/en-us/azure/virtual-desktop/
# Author: Nicholas Eckermann
# Email: nicholas.eckermann@gmail.com
# 

# Tenant we are working with
$onmicosofttenant = Read-Host -Prompt 'Tenant we are working with, example client.onmicrosoft.com'


# Verify Modules needed are installed
# Install Azure PowerShell Module
if (! (Get-InstalledModule -Name Az -AllVersions)){
    Install-Module -Name Az -AllowClobber -Scope AllUsers
} else {Write-Host 'Azure Module Already Installed'}

# Install Windows Virutal Desktop PowerShell Module
if (! ( Get-InstalledModule -Name Microsoft.RDInfra.RDPowerShell -AllVersions)){
    Install-Module -Name Microsoft.RDInfra.RDPowerShell
} else {Write-Host 'Windows Virtual Desktop Module Already Installed'}
# Install AzureAd PowerShell Module
if (! ( Get-InstalledModule -Name AzureAD -AllVersions)){
    Install-Module -Name AzureAD
} else {Write-Host 'AzureAD Module Already Installed'}

# Grant permissions to Windows Virtual Desktop
# https://docs.microsoft.com/en-us/azure/virtual-desktop/tenant-setup-azure-active-directory#grant-permissions-to-windows-virtual-desktop

Start 'https://login.microsoftonline.com/common/adminconsent?client_id=5a0aa725-4958-4b0c-80a9-34562e23f3b7&redirect_uri=https%3A%2F%2Frdweb.wvd.microsoft.com%2FRDWeb%2FConsentCallback'

# Allow time to grant permissions
Start-Sleep -Seconds 60

# Get AadTenantId
Connect-AzAccount
$AadTenatnId = (Get-AzTenant).Id

# Get Azure Subscriptions and select subscription
Get-AzSubscription
$AzureSub = Read-Host -Prompt 'What Auzre Subscription would you like to use for the WVD Tenant, copy and past from above available subscriptions'

# Connect and create WVD tenant
Add-RdsAccount -DeploymentUrl "https://rdbroker.wvd.microsoft.com"

# Create a new Windows Virtual Desktop tenant associated with the Azure Active Directory tenant
# https://docs.microsoft.com/en-us/azure/virtual-desktop/tenant-setup-azure-active-directory#create-a-windows-virtual-desktop-tenant
New-RdsTenant -Name $onmicosofttenant -AadTenantId $AadTenatnId -AzureSubscriptionId $AzureSub


# Create service principals and role assignments
# https://docs.microsoft.com/en-us/azure/virtual-desktop/create-service-principal-role-powershell
$aadContext = Connect-AzureAD
$svcPrincipal = New-AzureADApplication -AvailableToOtherTenants $true -DisplayName "Windows Virtual Desktop Svc Principal"
$svcPrincipalCreds = New-AzureADApplicationPasswordCredential -ObjectId $svcPrincipal.ObjectId

# Before you create the role assignment for your service principal, view your credentials and write them down!
# https://docs.microsoft.com/en-us/azure/virtual-desktop/create-service-principal-role-powershell#view-your-credentials-in-powershell
Write-Host 'Before you create the role assignment for your service principal, view your credentials and write them down! We will also create a CSV file backup' -BackgroundColor Red
$svcPrincipalCreds.Value
$aadContext.TenantId.Guid
$svcPrincipal.AppId

$PathToBackupServicePrincipalCredInfo = Read-Host 'Where would you like to backup your Service Principal Account information to CSV, example c:\admin'
# Create Directory if does not exist
if (! (Test-Path -Path $PathToBackupServicePrincipalCredInfo)){
    New-Item -Path $PathToBackupServicePrincipalCredInfo -ItemType Directory|Out-Null
}
    $ServicePrincipalInfo=[ordered]@{
            'Service Principal Creds' = $svcPrincipalCreds.Value
            'AzureADContext Tenant Guid' = $aadContext.TenantId.Guid
            'Service Principal AppId' = $svcPrincipal.AppId
            }
        $obj=New-Object -TypeName PSObject -Property $ServicePrincipalInfo |Export-Csv -NoTypeInformation -Path "$PathToBackupServicePrincipalCredInfo\WVDServicePrincipal.csv"


# Create a role assignment in Windows Virtual Desktop
# https://docs.microsoft.com/en-us/azure/virtual-desktop/create-service-principal-role-powershell#create-a-role-assignment-in-windows-virtual-desktop-preview
Add-RdsAccount -DeploymentUrl "https://rdbroker.wvd.microsoft.com"
$TenantName = (Get-RdsTenant).TenantName

$myTenantName = "$TenantName"
New-RdsRoleAssignment -RoleDefinitionName "RDS Owner" -ApplicationId $svcPrincipal.AppId -TenantName $myTenantName

# Test Service Principal account
# https://docs.microsoft.com/en-us/azure/virtual-desktop/create-service-principal-role-powershell#sign-in-with-the-service-principal
$creds = New-Object System.Management.Automation.PSCredential($svcPrincipal.AppId, (ConvertTo-SecureString $svcPrincipalCreds.Value -AsPlainText -Force))
Add-RdsAccount -DeploymentUrl "https://rdbroker.wvd.microsoft.com" -Credential $creds -ServicePrincipal -AadTenantId $aadContext.TenantId.Guid


# Create a host pool with PowerShell
# https://docs.microsoft.com/en-us/azure/virtual-desktop/create-host-pools-powershell
# Connect to WVD
Add-RdsAccount -DeploymentUrl "https://rdbroker.wvd.microsoft.com"

# Create WVD host pool
$HostPoolName = Read-Host -Prompt 'What do you want the name of the host pool to be?'
New-RdsHostPool -TenantName $onmicosofttenant -Name $HostPoolName

# Prompt for users to add to pool
$UsersToAddToHostPool = @()
do {
 $UPNInput = (Read-Host -Prompt "Enter UPNs for each user your adding to RDSUserGroup, enter blank line to finish gathering users")
 if ($UPNInput -ne '') {$UsersToAddToHostPool += $UPNInput}
}
until ($UPNInput -eq '')

foreach ($UserToAddToHostPool in $UsersToAddToHostPool){

Add-RdsAppGroupUser -TenantName $onmicosofttenant -HostPoolName $HostPoolName -AppGroupName "Desktop Application Group" -UserPrincipalName $UserToAddToHostPool
}

#Create registration token to authorize a session host to join the host pool

$PathToBackupHostPoolRegToken = Read-Host 'Where would you like to backup HostPool Registration Token, example c:\admin'
# Create Directory if does not exist
if (! (Test-Path -Path $PathToBackupHostPoolRegToken)){
    New-Item -Path $PathToBackupHostPoolRegToken -ItemType Directory|Out-Null
}

New-RdsRegistrationInfo -TenantName $onmicosofttenant -HostPoolName $HostPoolName | Select-Object -ExpandProperty Token > "$PathToBackupHostPoolRegToken\HostPoolRegToken.txt"

$HostPoolSessionHostToken = (Export-RdsRegistrationInfo -TenantName $onmicosofttenant -HostPoolName $HostPoolName).Token
Write-Host -Object "Your HostPool Registration Token for registing your SessionHost to the $HostPoolName host pool is $HostPoolSessionHostToken" -BackgroundColor Red


<#
# Create a host pool by using the Azure Marketplace
# https://docs.microsoft.com/en-us/azure/virtual-desktop/create-host-pools-azure-marketplace

Add-RdsAccount -DeploymentUrl "https://rdbroker.wvd.microsoft.com"

Start 'https://portal.azure.com/'


Write-Host "Windows Virtual Desktop tenant information`
For the Windows Virtual Desktop tenant information blade:`
`
For Windows Virtual Desktop tenant group name, enter the name for the tenant group that contains your tenant. Leave it as the default unless you were provided a specific tenant group name.`
For Windows Virtual Desktop tenant name, enter the name of the tenant where you'll be creating this host pool.`
Specify the type of credentials that you want to use to authenticate as the Windows Virtual Desktop tenant RDS Owner. If you completed the Create service principals and role assignments with PowerShell tutorial, select Service principal. When Azure AD tenant ID appears, enter the ID for the Azure Active Directory instance that contains the service principal.`
Enter the credentials for the tenant admin account. Only service principals with a password credential are supported.`
Select OK.`
"

#

#Add users to host pool


Add-RdsAppGroupUser $onmicosofttenant <hostpoolname> "Desktop Application Group" -UserPrincipalName <userupn>
#>