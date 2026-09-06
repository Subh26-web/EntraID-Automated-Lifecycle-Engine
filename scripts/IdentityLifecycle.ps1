<#
================================================================================
  ENTERPRISE IDENTITY LIFECYCLE MANAGEMENT ENGINE (JML)
  Technology: Microsoft Entra ID | Microsoft Graph PowerShell SDK
  Author: Subhra Banik
  Execution Mode: High-Volume Batch Lifecycle Management (Joiner, Mover, Leaver)
================================================================================
#>

# Enforce TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$requiredScopes = @(
    "User.ReadWrite.All",
    "Directory.ReadWrite.All",
    "GroupMember.ReadWrite.All",
    "AdministrativeUnit.ReadWrite.All"
)

Write-Host "`n[*] Initializing Microsoft Graph API Connection..." -ForegroundColor Cyan
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

# Discover Verified Tenant Domain
$tenantDomain = (Get-MgOrganization | Select-Object -ExpandProperty VerifiedDomains | Where-Object { $_.IsDefault }).Name
Write-Host "[+] Target Directory Domain: $tenantDomain" -ForegroundColor Green

$csvPath = ".\data\HR_Feed.csv"
if (-not (Test-Path $csvPath)) {
    # Fallback to local directory if executed from root
    $csvPath = ".\HR_Feed.csv"
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFolder = ".\logs"
if (-not (Test-Path $logFolder)) {
    New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
}
$logPath = "$logFolder\JML_Audit_Log_$timestamp.csv"
$auditRecords = @()

if (-not (Test-Path $csvPath)) {
    Write-Error "[-] HR_Feed.csv not found in .\data\ or current folder."
    return
}

$employees = Import-Csv $csvPath
$totalCount = $employees.Count
$counter = 0

Write-Host "[*] Ingesting $totalCount identity records from HR feed...`n" -ForegroundColor Cyan

foreach ($emp in $employees) {
    $counter++
    $upn = "$($emp.FirstName.ToLower()).$($emp.LastName.ToLower())@$tenantDomain"
    $progressTag = "[$counter/$totalCount]"

    switch ($emp.State) {
        
        # =====================================================================
        # WORKFLOW 1: BATCH JOINER
        # =====================================================================
        "Joiner" {
            Write-Host "$progressTag Provisioning: $upn" -ForegroundColor Green
            
            # Idempotency Check
            $existingUser = Get-MgUser -Filter "UserPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
            if ($existingUser) {
                Write-Host "    [!] User already exists in directory. Skipping creation." -ForegroundColor Yellow
                $auditRecords += [PSCustomObject]@{
                    Timestamp   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    Action      = "JOINER_SKIPPED"
                    UserUPN     = $upn
                    Department  = $emp.Department
                    Status      = "EXISTS"
                    Details     = "Identity already active in directory."
                }
                continue
            }

            # Generate distinct temporary password
            $tempPassword = "ContosoInit!" + (Get-Random -Minimum 1000 -Maximum 9999) + "#"
            $passwordProfile = @{
                ForceChangePasswordNextSignIn = $true
                Password                      = $tempPassword
            }

            try {
                # Create User Object
                $newUser = New-MgUser -DisplayName "$($emp.FirstName) $($emp.LastName)" `
                                      -GivenName $emp.FirstName `
                                      -Surname $emp.LastName `
                                      -UserPrincipalName $upn `
                                      -MailNickname "$($emp.FirstName.ToLower()).$($emp.LastName.ToLower())" `
                                      -Department $emp.Department `
                                      -JobTitle $emp.JobTitle `
                                      -UsageLocation "IN" `
                                      -AccountEnabled:$true `
                                      -PasswordProfile $passwordProfile

                Write-Host "    -> Cloud Identity Created" -ForegroundColor Gray

                # Assign Scoped Administrative Unit (AU)
                $targetAU = Get-MgDirectoryAdministrativeUnit -Filter "DisplayName eq 'AU-$($emp.Department)'"
                if ($targetAU) {
                    New-MgDirectoryAdministrativeUnitMemberByRef -AdministrativeUnitId $targetAU.Id `
                        -ODataId "https://graph.microsoft.com/v1.0/directoryObjects/$($newUser.Id)"
                    Write-Host "    -> Scoped to Administrative Unit: AU-$($emp.Department)" -ForegroundColor Gray
                }

                $auditRecords += [PSCustomObject]@{
                    Timestamp   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    Action      = "JOINER_PROVISION"
                    UserUPN     = $upn
                    Department  = $emp.Department
                    Status      = "SUCCESS"
                    Details     = "Provisioned under AU-$($emp.Department); Dynamic group & license sync initiated."
                }
            }
            catch {
                Write-Host "    [-] Error creating $upn : $_" -ForegroundColor Red
                $auditRecords += [PSCustomObject]@{
                    Timestamp   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    Action      = "JOINER_ERROR"
                    UserUPN     = $upn
                    Department  = $emp.Department
                    Status      = "FAILED"
                    Details     = $_.Exception.Message
                }
            }
        }

        # =====================================================================
        # WORKFLOW 2: MOVER (With Automatic AU Re-scoping)
        # =====================================================================
        "Mover" {
            Write-Host "$progressTag Processing Mover: $upn" -ForegroundColor Yellow
            $user = Get-MgUser -Filter "UserPrincipalName eq '$upn'" -ErrorAction SilentlyContinue

            if ($user) {
                # 1. Update Core Profile
                Update-MgUser -UserId $user.Id -Department $emp.Department -JobTitle $emp.JobTitle
                
                # 2. Invalidate Active Session Tokens
                Revoke-MgUserSignInSession -UserId $user.Id | Out-Null
                Write-Host "    -> Updated to $($emp.Department) & Invalidated Active Tokens" -ForegroundColor Gray

                # 3. Purge Membership from ANY Other Departmental AU
                $allAUs = Get-MgDirectoryAdministrativeUnit
                foreach ($au in $allAUs) {
                    if ($au.DisplayName -like "AU-*" -and $au.DisplayName -ne "AU-$($emp.Department)") {
                        Remove-MgDirectoryAdministrativeUnitMemberByRef -AdministrativeUnitId $au.Id `
                            -DirectoryObjectId $user.Id -ErrorAction SilentlyContinue
                    }
                }

                # 4. Assign Target AU
                $targetAU = Get-MgDirectoryAdministrativeUnit -Filter "DisplayName eq 'AU-$($emp.Department)'"
                if ($targetAU) {
                    New-MgDirectoryAdministrativeUnitMemberByRef -AdministrativeUnitId $targetAU.Id `
                        -ODataId "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)" -ErrorAction SilentlyContinue
                    Write-Host "    -> Cleaned old AUs and moved to: AU-$($emp.Department)" -ForegroundColor Cyan
                }

                $auditRecords += [PSCustomObject]@{
                    Timestamp   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    Action      = "MOVER_TRANSFER"
                    UserUPN     = $upn
                    Department  = $emp.Department
                    Status      = "SUCCESS"
                    Details     = "Transferred to $($emp.Department); Cleaned stale AUs; Tokens revoked."
                }
            }
        }

        # =====================================================================
        # WORKFLOW 3: LEAVER (With Full AU & Entitlement Cleanup)
        # =====================================================================
        "Leaver" {
            Write-Host "$progressTag Offboarding Leaver: $upn" -ForegroundColor Red
            $user = Get-MgUser -Filter "UserPrincipalName eq '$upn'" -ErrorAction SilentlyContinue

            if ($user) {
                # 1. Disable Account Sign-in
                Update-MgUser -UserId $user.Id -AccountEnabled:$false

                # 2. Revoke Sessions & Refresh Tokens
                Revoke-MgUserSignInSession -UserId $user.Id | Out-Null

                # 3. Strip Direct Group Memberships
                $directGroups = Get-MgUserMemberOf -UserId $user.Id
                foreach ($grp in $directGroups) {
                    if ($grp.AdditionalProperties['@odata.type'] -eq "#microsoft.graph.group") {
                        Remove-MgGroupMemberByRef -GroupId $grp.Id -DirectoryObjectId $user.Id -ErrorAction SilentlyContinue
                    }
                }

                # 4. Strip Administrative Unit Memberships
                $allAUs = Get-MgDirectoryAdministrativeUnit
                foreach ($au in $allAUs) {
                    Remove-MgDirectoryAdministrativeUnitMemberByRef -AdministrativeUnitId $au.Id `
                        -DirectoryObjectId $user.Id -ErrorAction SilentlyContinue
                }

                Write-Host "    -> Account Disabled, Sessions Terminated, and Removed from all AUs & Groups" -ForegroundColor Gray

                $auditRecords += [PSCustomObject]@{
                    Timestamp   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    Action      = "LEAVER_OFFBOARD"
                    UserUPN     = $upn
                    Department  = $emp.Department
                    Status      = "SUCCESS"
                    Details     = "Sign-in disabled; CAE revoked; Removed from all Groups and Administrative Units."
                }
            }
        }
    } # Closes switch ($emp.State)
} # Closes foreach ($emp in $employees)

# Export Audit Evidence
if ($auditRecords.Count -gt 0) {
    $auditRecords | Export-Csv -Path $logPath -NoTypeInformation
    Write-Host "`n==================================================================" -ForegroundColor Cyan
    Write-Host "[*] Lifecycle automation complete. Audit log written to:" -ForegroundColor Green
    Write-Host "    $logPath" -ForegroundColor White
    Write-Host "==================================================================" -ForegroundColor Cyan
}