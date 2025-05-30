# Report-RoleAssignments.PS1
# Example script to show how to report Entra ID role assignments (PIM or direct) using the 
# Microsoft Graph PowerShell SDK
# V1.0 14-Aug-2024  Tested with SDK V2.22. Based on some original code tweeted by Nathan McNulty
# V2.0 10-Nov-2024  Updated to use the unifiedRoleDefinition API
# V2.1 12-Nov-2024  Changed to V1.0 endpoint and added group name for group assignments
# GitHub link: https://github.com/12Knocksinna/Office365itpros/blob/master/Report-RoleAssignments.PS1

Connect-MgGraph -Scopes RoleAssignmentSchedule.Read.Directory, RoleEligibilitySchedule.Read.Directory, Group.Read.All, GroupMember.Read.All -NoWelcome

# Find administrative units and load details into a hash table to speed up lookups
[array]$AdminUnits = Get-MgDirectoryAdministrativeUnit -Property Id, DisplayName | Sort-Object DisplayName
$AdminUnitsHash = @{}
ForEach ($AU in $AdminUnits) {
    $AdminUnitsHash.Add($AU.Id, $AU.DisplayName)
}

# Output report
$Report = [System.Collections.Generic.List[Object]]::new()

Write-Host "Checking for PIM active assignments..."
# Get active assignments
[array]$ActiveAssignments = Get-MgRoleManagementDirectoryRoleAssignmentSchedule `
    -ExpandProperty RoleDefinition, Principal -All 

Write-Host ("Found {0} PIM active assignments" -f $ActiveAssignments.Count)

ForEach ($Assignment in $ActiveAssignments) {
    $AdminUnitId = $null; $AdminUnitName = $null; $ServicePrincipal = $null; $AppId = $null; $OnPremisesUser = $false
    # Check scoping for assignment
    If ($Assignment.DirectoryScopeId -ne "/") {
        $AdminUnitId = $Assignment.DirectoryScopeId.SubString(21,$Assignment.DirectoryScopeId.Length-21)
        $AdminUnitName = $AdminUnitsHash[$AdminUnitId] 
    } Else {
        $AdminUnitName = "Complete directory"
    }
    $RoleName = $Assignment.RoleDefinition.DisplayName
    If ($Assignment.Principal.AdditionalProperties.onPremisesSyncEnabled) {
        $OnPremisesUser = $true
    }

    Switch ($Assignment.Principal.AdditionalProperties."@odata.type") {
        "#microsoft.graph.user" {     

            $ReportLine = [PSCustomObject][Ordered]@{
                RoleName            = $RoleName
                UserPrincipalName   = $Assignment.Principal.AdditionalProperties.userPrincipalName
                Created             = $Assignment.CreatedDateTime
                DirectoryScope      = $adminUnitName
                OnPremisesUser      = $OnPremisesUser
                AssignmentType      = "Active (PIM)"
                AssignmentVia       = "User"
                MemberType          = $Assignment.MemberType
            }
            $Report.Add($ReportLine)
        }
    # Process group assignments
        "#microsoft.graph.group" {
            
            [array]$Members = (Get-MgGroupMember -GroupId $Assignment.Principal.Id)
            If ($Members) { 
                $GroupName = (Get-MgGroup -GroupId $Assignment.Principal.Id).DisplayName
                ForEach ($Member in $Members) {
                    $ReportLine = [PSCustomObject][Ordered]@{
                        RoleName            = $RoleName
                        UserPrincipalName   = $Member.AdditionalProperties.userPrincipalName
                        Created             = $Assignment.CreatedDateTime
                        DirectoryScope      = $AdminUnitName
                        OnPremisesUser      = $OnPremisesUser
                        AssignmentType      = "Active (PIM)"
                        AssignmentVia       = ("{0} (Group)" -f $GroupName)
                        MemberType          = $Assignment.MemberType
                    }
                    $Report.Add($ReportLine)
                }
            }
        }   
        "#microsoft.graph.servicePrincipal" {

            $AppId = $Assignment.Principal.AdditionalProperties.appId
            $ServicePrincipal = (Get-MgServicePrincipal -Filter "AppId eq '$AppId'").DisplayName
            $ReportLine = [PSCustomObject][Ordered]@{
                RoleName            = $RoleName
                UserPrincipalName   = $Assignment.Principal.AdditionalProperties.displayName
                Created             = $Assignment.CreatedDateTime
                DirectoryScope      = $AdminUnitName
                OnPremisesUser      = $false
                AssignmentType      = "Active (PIM)"
                AssignmentVia       = "Service Principal"
                MemberType          = $Assignment.MemberType
                SPName              = $ServicePrincipal
            }
            $Report.Add($ReportLine)
        }
    }

}    

Write-Host "Checking for PIM eligible assignments..."

# Get eligible assignments
[array]$EligibleAssignments = Get-MgRoleManagementDirectoryRoleEligibilitySchedule `
    -ExpandProperty RoleDefinition, Principal  -All 
Write-Host ("Found {0} PIM eligible assignments" -f $EligibleAssignments.Count)

ForEach ($Assignment in $EligibleAssignments) {
    $AdminUnitId = $null; $AdminUnitName = $null; $ServicePrincipal = $null; $AppId = $null; $OnPremisesUser = $false
    # Check scoping for assignment
    If ($Assignment.DirectoryScopeId -ne "/") {
        $AdminUnitId = $Assignment.DirectoryScopeId.SubString(21,$Assignment.DirectoryScopeId.Length-21)
        $AdminUnitName = $AdminUnitsHash[$AdminUnitId] 
    } Else {
        $AdminUnitName = "Complete directory"
    }
    $RoleName = $Assignment.RoleDefinition.DisplayName
    $OnPremisesUser = $false

    If ($Assignment.Principal.AdditionalProperties.onPremisesSyncEnabled) {
        $OnPremisesUser = $true
    }

    Switch ($Assignment.Principal.AdditionalProperties."@odata.type") {
        "#microsoft.graph.user" {  
            $ReportLine = [PSCustomObject][Ordered]@{
                RoleName            = $RoleName
                UserPrincipalName   = $Assignment.Principal.AdditionalProperties.userPrincipalName
                Created             = $Assignment.CreatedDateTime
                DirectoryScope      = $adminUnitName
                OnPremisesUser      = $OnPremisesUser
                AssignmentType      = "Eligible"
                AssignmentVia       = "User"
                MemberType          = $Assignment.MemberType
            }
            $Report.Add($ReportLine)
        }
        # Process group assignments
        "#microsoft.graph.group" {
            
            [array]$Members = (Get-MgGroupMember -GroupId $Assignment.Principal.Id)
            If ($Members) { 
                $GroupName = (Get-MgGroup -GroupId $Assignment.Principal.Id).DisplayName
                ForEach ($Member in $Members) {
                    $ReportLine = [PSCustomObject][Ordered]@{
                        RoleName            = $RoleName
                        UserPrincipalName   = $Member.AdditionalProperties.userPrincipalName
                        Created             = $Assignment.CreatedDateTime
                        DirectoryScope      = $AdminUnitName
                        OnPremisesUser      = $OnPremisesUser
                        AssignmentType      = "Eligible"
                        AssignmentVia       = ("{0} (Group)" -f $GroupName)
                        MemberType          = $Assignment.MemberType
                    }
                    $Report.Add($ReportLine)
                }
            }
        }   
        "#microsoft.graph.servicePrincipal" {

            $AppId = $Assignment.Principal.AdditionalProperties.appId
            $ServicePrincipal = (Get-MgServicePrincipal -Filter "AppId eq '$AppId'").DisplayName
            $ReportLine = [PSCustomObject][Ordered]@{
                RoleName            = $RoleName
                UserPrincipalName   = $Assignment.Principal.AdditionalProperties.displayName
                Created             = $Assignment.CreatedDateTime
                DirectoryScope      = $AdminUnitName
                OnPremisesUser      = $OnPremisesUser
                AssignmentType      = "Eligible"
                AssignmentVia       = "Service Principal"
                MemberType          = $Assignment.MemberType
                SPName              = $ServicePrincipal
            }
            $Report.Add($ReportLine)
        }
    }
}

$PIMAssignments = $ActiveAssignments.count + $EligibleAssignments.count
If ($PIMAssignments -eq 0) {
    # Tenant must not be using PIM, so let's interrogate the unified directory roles for direct permanent assignments instead
    [array]$DirectoryRoles = Get-MgRoleManagementDirectoryRoleDefinition -All

    ForEach ($Role in $DirectoryRoles) {
        $RoleId = $Role.Id
        [array]$RoleMembers = Get-MgRoleManagementDirectoryRoleAssignment -Filter "roleDefinitionId eq '$RoleId'" 
        If ($RoleMembers) {
            $RoleName = $Role.DisplayName      
            ForEach ($Member in $RoleMembers) {
                $MemberDetails = Get-MgUser -UserId $Member.PrincipalId -ErrorAction SilentlyContinue
                If ($MemberDetails) {
                    If ($User.OnPremisesSyncEnabled) {
                        $OnPremisesStatus = $User.OnPremisesSyncEnabled
                    } Else {
                        $OnPremisesStatus = "N/A"
                    }
                    $ReportLine = [PSCustomObject][Ordered]@{
                        RoleName            = $RoleName
                        UserPrincipalName   = $MemberDetails.UserPrincipalName
                        DirectoryScope      = "Entire Directory"
                        OnPremisesUser      = $OnPremisesStatus
                        AssignmentType      = "User"  
                        MemberType          = "Direct (non-PIM)"
                    }
                    Continue
                }
                $MemberDetails = Get-MgServicePrincipal -ServicePrincipalId $Member.PrincipalId -ErrorAction SilentlyContinue
                If ($MemberDetails) {
                    $ReportLine = [PSCustomObject][Ordered]@{
                        RoleName            = $RoleName
                        UserPrincipalName   = $MemberDetails.DisplayName
                        DirectoryScope      = "Entire directory"
                        OnPremisesUser      = "N/A"
                        AssignmentType      = "Service Principal"  
                        MemberType          = "Direct (non-PIM)"
                    }
                    Continue
                }   
                $MemberDetails = Get-MgGroup -GroupId $Member.PrincipalId -ErrorAction SilentlyContinue
                If ($MemberDetails) {
                    $ReportLine = [PSCustomObject][Ordered]@{
                        RoleName            = $RoleName
                        UserPrincipalName   = $MemberDetails.DisplayName
                        DirectoryScope      = "Entire directory"
                        OnPremisesUser      = "N/A"
                        AssignmentType      = "Group"  
                        MemberType          = "Direct (non-PIM)"
                    }
                }   
                $Report.Add($ReportLine)
            }
        }   
    }
}

Write-Host "All done. Reporting information..."

$Report | Sort-Object {$_.Created -as [datetime]} | Out-GridView -Title "Role Assignments Report" 
[array]$OnPremisesUsers = $Report | Where-Object {$_.OnPremisesUser -ne $false -and $_.AssignmentVia -eq "User"} | `
    Sort-Object UserPrincipalName -Unique

# Generate the report in either Excel worksheet or CSV format, depending on if the ImportExcel module is available
If (Get-Module ImportExcel -ListAvailable) {
    $ExcelGenerated = $True
    Import-Module ImportExcel -ErrorAction SilentlyContinue
    $ExcelOutputFile = ((New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path) + "\RoleAssignments.xlsx"
    $Report | Export-Excel -Path $ExcelOutputFile -WorksheetName "Role Assignments" -Title ("Role Assignments Report {0}" -f (Get-Date -format 'dd-MMM-yyyy')) -TitleBold -TableName "Microsoft365LicensingReport" 
} Else {
    $CSVOutputFile = ((New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path) + "\RoleAssignments.CSV"
    $Report | Export-Csv -Path $CSVOutputFile -NoTypeInformation -Encoding Utf8
}

Write-Host ""
Write-Host "Report completed"
Write-Host "----------------"
Write-Host ("Reported {0} PIM assignments" -f $Report.count)

If ($ExcelGenerated -eq $true) {
    Write-Host ("Role Assignments report available in Excel workbook {0}" -f $ExcelOutputFile)
} Else {
    Write-Host ("Role Assignments report available in CSV file {0}" -f $CSVOutputFile)
}

If ($OnPremisesUsers) {
    Write-Host ""
    Write-Host ("{0} assignments are for on-premises users" -f $OnPremisesUsers.count)
    Write-Host ""
    $OnPremisesUsers.UserPrincipalName
} Else {
    Write-Host "No assignments found for on-premises users"
}

# An example script used to illustrate a concept. More information about the topic can be found in the Office 365 for IT Pros eBook https://gum.co/O365IT/
# and/or a relevant article on https://office365itpros.com or https://www.practical365.com. See our post about the Office 365 for IT Pros repository 
# https://office365itpros.com/office-365-github-repository/ for information about the scripts we write.

# Do not use our scripts in production until you are satisfied that the code meets the needs of your organization. Never run any code downloaded from the Internet without
# first validating the code in a non-production environment.