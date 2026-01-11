[![License](https://img.shields.io/badge/License-Broadcom-green.svg)](LICENSE.md)
[![PowerShell](https://img.shields.io/badge/PowerShell-7.2%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![PowerCLI](https://img.shields.io/badge/VCF.PowerClI-9.0%2B-red.svg)](https://www.powershellgallery.com/packages/)
[![GitHub Clones](https://img.shields.io/badge/dynamic/json?color=success&label=Clone&query=count&url=https://gist.githubusercontent.com/nathanthaler/f02ea07c5010c0c095cd9707622670b3/raw/clone.json&logo=github)](https://gist.githubusercontent.com/nathanthaler/f02ea07c5010c0c095cd9707622670b3/raw/clone.json)
![Downloads](https://img.shields.io/github/downloads/vmware/powershell-script-for-vmware-cloud-foundation-vum-unrestrict/total?label=Release%20Downloads)
[![Changelog](https://img.shields.io/badge/Changelog-Read-blue)](CHANGELOG.md)

# VMware Cloud Foundation VUM Unrestrict Script

Temporarily allow vCenter VMware Update Manager (VUM) to enable the transition of heterogeneous hardware to vLCM Image Management.  VMware Update Manager will remain enabled until the service or the vCenter appliance is restarted.

## Overview

To complete your upgrade to VCF 9, you must transition your clusters from vLCM baseline management to vLCM image management.

The ESX upgrade portion of VMware Cloud Foundation 9.x upgrade process has a prerequisite of vLCM image-managed clusters.

However, vLCM images for heterogeneous hardware-based clusters are only supported in ESX 9, which means the transition must occur after the ESX 9 upgrade. In order to upgrade heterogeneous-hardware clusters to ESX 9 using VUM, a special process is required to temporarily allow the service.

The vCenter Update Manager service can be unrestricted via a Broadcom-provided PowerShell script or vCenter APIs, but only if one or more heterogeneous-hardware clusters are present.

Once vCenter Update Manager has been unrestricted, please upgrade the heterogeneous cluster to ESX 9 using vCenter Update Manager and then [transition the cluster to vLCM images](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-0/deployment/upgrading-cloud-foundation/upgrade-the-management-domain-to-vmware-cloud-foundation-5-2/vlcm-baseline-to-vlcm-image-cluster-transition-.html).

## Modes

This script can work in VCF Mode (through SDDC Manager) and vCenter mode (no SDDC Manager).  The former detects and connects all vCenters registered to SDDC manager, while the latter connects to individual vCenters.

## Caveats

- This process is only supported for true heterogeneous clusters.
- The service becomes restricted after a service restart or appliance reboot.
- Following VUM-based ESX 9 upgrades, users should prioritize transitioning the cluster(s) from vLCM baselines to vLCM images.

## Option 1: PowerShell (Preferred)

### Requirements

#### Client Software

- [VCF.PowerCLI 9.0+](https://developer.broadcom.com/powercli)
- [PowerShell 7.2+](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell)
- Compatible OS: MacOS / Linux / Windows

Note: Before installing VCF.PowerCLI [uninstall VMware.PowerCLI](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/power-cli/latest/powercli/installing-vmware-vsphere-powercli/uninstall-powercli.html) to avoid conflicts between the two modules.

#### User Rights

- (for VCF Mode) SDDC Manager: ADMIN user
- (for vCenter Mode) vCenter : ADMIN access

#### Network Permissions

- HTTPS access to SDDC Manager
- HTTPS access to vCenter

#### Server Software

- SDDC Manager 9.0+ (for VCF mode)
- vCenter 9.0+ (for the heterogeneous clusters)

### Download

Link to [latest](https://github.com/vmware/powershell-script-for-vmware-cloud-foundation-vum-unrestrict/releases/latest/download/VumUnrestrict.zip) release.

### Issue Reporting

Log any issues here:

<https://github.com/vmware/powershell-script-for-vmware-cloud-foundation-vum-unrestrict/issues>

### Usage

### Option 1: Choosing a mode interactively
- Run `VumUnrestrict.ps1`. If you have a VCF deployment with SDDC Manager, enter "Y" to the prompt `Is this a VCF Deployment?` otherwise enter "N".
- When prompted, enter the credentials for SDDC Manager or vCenter, depending on the mode.

### Option 2: Choosing a mode via Parameter
 -Run `VumUnrestrict.ps1 -Mode VCF` for VCF mode (with SDDC Manager) or `VumUnrestrict.ps1 -Mode vCenter` (for non-VCF mode without SDDC Manager)
- When prompted, enter the credentials for SDDC Manager or vCenter, depending on the mode.

### Status Codes

The script will return one of four statuses:

|Status|Meaning|Action Required / Next Steps|
|---|---|---|
|N/A|vCenter version not supported|Upgrade to vCenter 9.0 or later|
|Unrestricted|Success - VUM Services Unrestricted|Ready to proceed to ESX 9.0 upgrade|
|Restricted|No heterogeneous hardware-clusters located|Any VUM based clusters can be transitioned to vLCM images|
|Failed|Underlying vCenter Task failed, was blocked, or entered an unknown state|Please open a support case|

### Example 1: VCF Mode (with SDDC Manager)

```Powershell
PS> .\VumUnrestrict.ps1

Is this a VCF Deployment?
[Y] Yes  [N] No  [?] Help (default is "Y"):

[INFO] Please enter your connection details at the prompt.

Enter your SDDC Manager FQDN: vcf01.example.com
Enter your SDDC Manager SSO username: administrator@vsphere.local
Enter your SDDC Manager SSO password: ********

[INFO] Successfully connected to SDDC Manager "vcf01.example.com" as "administrator@vsphere.local".

[INFO] Successfully connected to vCenter "vcenter01.example.com".

[WARNING] vCenter "vcenter02.example.com" detected running version 8.0. vCenter 9.0 or later required.

[INFO] Disconnecting from incompatible vCenter "vcenter02.example.com".

[INFO] Successfully disconnected from vCenter "vcenter02.example.com".

[INFO] Looking for heterogeneous-hardware clusters in the connected vCenter(s)...

[INFO] vCenter "vcenter01.example.com" VUM unrestrict task completed in 29 seconds.

Summary:

vCenter               VUM Services     Message
-------               ------------     -------
vcenter01.example.com Unrestricted     Heterogeneous-hardware clusters(s) located.
vcenter02.example.com N/A              vCenter release unsupported (version 8.0).

[INFO] Successfully disconnected from SDDC Manager "vcenter01.example.com".

[INFO] Successfully disconnected from vCenter "vcenter01.example.com".
```

### Example 2: vCenter Mode (heterogeneous cluster found)

```Powershell

PS> .\VumUnrestrict.ps1

Is this a VCF Deployment?
[Y] Yes  [N] No  [?] Help (default is "Y"): N

[INFO] Please enter your vCenter connection details at the prompt.

Enter your vCenter FQDN: vcenter01.example.com
Enter your vCenter SSO username: administrator@vsphere.local
Enter your vCenter SSO password: ********

[INFO] Successfully connected to vCenter "vcenter01.example.com" as "administrator@vsphere.local".

[INFO] Looking for heterogeneous-hardware clusters in the connected vCenter(s)...

[INFO] vCenter "vcenter01.example.com" VUM unrestrict task completed in 25 seconds.

Summary:

vCenter                      VUM Services     Message
-------                      ------------     -------
vcenter01.example.com        Unrestricted     Heterogeneous-hardware clusters(s) located.

[INFO] Successfully disconnected from vCenter "vcenter01.example.com".
```

### Example 3: vCenter Mode (incompatible vCenter found)

```Powershell

PS> .\VumUnrestrict.ps1

Is this a VCF Deployment?
[Y] Yes  [N] No  [?] Help (default is "Y"): N

[INFO] Please enter your vCenter connection details at the prompt.

Enter your vCenter FQDN: vcenter02.example.com
Enter your vCenter SSO username: administrator@vsphere.local
Enter your vCenter SSO password: ********

[INFO] Disconnecting from incompatible vCenter "vcenter02.example.com".

[ERROR] vCenter version 8.0 detected. Version 9.0 or later is required.
```

## Option 2: API (Using Developer Center)

### API Requirements

#### API User Rights

- vCenter: Administrative rights

#### API Network Permissions

- HTTPS access to vCenter

#### API Server Software

- vCenter 9.0+ (for the heterogeneous clusters)

### Steps

1. Login to vCenter as an administrative user.
2. Click on the Menu icon.
3. Click on Developer Center.
4. Click on API explorer.
5. Select API endpoint "esx".
6. Select the correct vCenter 9.0 or later endpoint.
7. Expand "settings/inventory".
8. Execute `/api/esx/settings/inventory?action=update-vum-capability&vmw-task=true`.
9. You receive a task ID back, copy this down (for example `"52b3cef6-00df-033a-9778-f243a1e96e97:com.vmware.esx.settings.inventory"`). If you do not get a task ID, please verify the vCenter in question was indeed running vCenter 9.0 or later.
10. Change your API endpoint to "cis".
11. Expand "tasks".
12. Expand `/api/cis/tasks/{tasks}/{task}`.
13. Enter your task ID from step 9 into the task field and click "Execute".
14. Look at `vum_operations_enabled` under results. If this key is equal to `true`, VUM has been unrestricted. If the value is `false`, please examine the payload for answers as to why not.

## Support

- For product issues, please open a standard Broadcom support case.
- For bugs or enhancement requests with this script, please open a [github issue](https://github.com/vmware/powershell-script-for-vmware-cloud-foundation-vum-unrestrict/issues).
