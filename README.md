[![License](https://img.shields.io/badge/License-Broadcom-green.svg)](LICENSE.md)
[![PowerShell](https://img.shields.io/badge/PowerShell-7.2%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![GitHub Clones](https://img.shields.io/badge/dynamic/json?color=success&label=Clone&query=count&url=https://gist.githubusercontent.com/nathanthaler/f02ea07c5010c0c095cd9707622670b3/raw/clone.json&logo=github)](https://gist.githubusercontent.com/nathanthaler/f02ea07c5010c0c095cd9707622670b3/raw/clone.json)


# VMware Cloud Foundation VUM Unrestrict Script

Temporarily allow vCenter VMware Update Manager (VUM) to enable the transition of heterogeneous hardware to vLCM Image Management.

## Overview

To complete your upgrade to VCF 9, you must transition your clusters from vLCM baseline management to vLCM image management.

The ESX upgrade portion of VMware Cloud Foundation 9.x upgrade process has a prerequisite of vLCM image-managed clusters.

However, vLCM images for heterogeneous hardware-based clusters are only supported in ESX 9, which means the transition must occur after the ESX 9 upgrade. In order to upgrade heterogeneous-hardware clusters to ESX 9 using VUM, a special process is required to temporarily allow the service.

The vCenter Update Manager service can be unrestricted via a Broadcom-provided PowerShell script or vCenter APIs, but only if one or more heterogeneous-hardware clusters are present.

## Caveats

- This process is only supported for true heterogeneous clusters.
- The service becomes restricted after a service restart or appliance reboot.
- Following VUM-based ESX 9 upgrades, users should prioritize transitioning the cluster(s) from vLCM baselines to vLCM images.

## Option 1: PowerShell (Preferred)

### Requirements

#### Client Software

<table>
  <thead>
    <tr>
      <th align="left">Software Component</th>
      <th align="left">Version/OS</th>
      <th align="left">Implementation Notes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>VCF PowerCLI</strong></td>
      <td>9.0 or later</td>
      <td>
        <strong>Critical:</strong>
        <a href="https://techdocs.broadcom.com/us/en/vmware-cis/vcf/power-cli/latest/powercli/installing-vmware-vsphere-powercli/uninstall-powercli.html">
          Uninstall VMware.PowerCLI
        </a>
        before installing VCF.PowerCLI.
      </td>
    </tr>
    <tr>
      <td><strong>PowerShell</strong></td>
      <td>7.2 or later</td>
      <td>Required for script execution.</td>
    </tr>
    <tr>
      <td><strong>Operating System</strong></td>
      <td>Cross-platform</td>
      <td>macOS, Linux, and Windows supported.</td>
    </tr>
  </tbody>
</table>

#### User Rights

<table>
  <thead>
    <tr>
      <th align="left">System</th>
      <th align="left">Required Role/User</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>SDDC Manager</strong></td>
      <td><code>ADMIN</code> user</td>
    </tr>
  </tbody>
</table>

#### Network Permissions

<table>
  <thead>
    <tr>
      <th align="left">Target</th>
      <th align="left">Protocol</th>
      <th align="left">Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>SDDC Manager</strong></td>
      <td>HTTPS (443)</td>
      <td>Inbound API and UI access.</td>
    </tr>
    <tr>
      <td><strong>vCenter</strong></td>
      <td>HTTPS (443)</td>
      <td>Inbound management access.</td>
    </tr>
  </tbody>
</table>

#### Server Software

<table>
  <thead>
    <tr>
      <th align="left">Server Component</th>
      <th align="left">Minimum Version</th>
      <th align="left">Context</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>SDDC Manager</strong></td>
      <td>9.0 or later</td>
      <td>Source WLD details.</td>
    </tr>
    <tr>
      <td><strong>vCenter</strong></td>
      <td>9.0 or later</td>
      <td>Required for heterogeneous cluster support.</td>
    </tr>
  </tbody>
</table>

### Download

Download the PowerShell script from:

<https://github.com/vmware/powershell-script-for-vmware-cloud-foundation-vum-unrestrict/>

### Issue Reporting

Log any issues here:

<https://github.com/vmware/powershell-script-for-vmware-cloud-foundation-vum-unrestrict/issues>

### Usage

Run `VumUnrestrict.ps1`. When prompted, please enter your SDDC manager FQDN, username, and password.

### Status Codes

The script will return one of four statuses:

|Status|Meaning|Action Required / Next Steps|
|---|---|---|
|N/A|vCenter version not supported|Upgrade to vCenter 9.0 or later|
|Unrestricted|Success - VUM Services Unrestricted|Ready to proceed to ESX 9.0 upgrade|
|Restricted|No heterogeneous hardware-clusters located|Any VUM based clusters can be transitioned to vLCM images|
|Failed|Underlying vCenter Task failed, was blocked, or entered an unknown state|Please open a support case|

### Example Output

```powershell
PS> .\VumUnrestrict.ps1

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

## Option 2: API (Using Developer Center)

### API Requirements

#### API User Rights

- vCenter: Administrative rights

#### API Network Permissions

- HTTPS access to vCenter

#### API Server Software

- vCenter 9.0 or later (for the heterogeneous clusters)

### Steps

1. Login to vCenter as an administrative user.
2. Click on the Menu icon.
3. Click on Developer Center.
4. Click on API explorer.
5. Select API endpoint "esx".
6. Select the correct vCenter 9.0 or later endpoint.
7. Expand "settings/inventory".
8. Expand `/api/esx/settings/inventory?action=update-vum-capability&vmw-task=true`.
9. You receive a task ID back, copy this down (for example `"52b3cef6-00df-033a-9778-f243a1e96e97:com.vmware.esx.settings.inventory"`). If you do not get a task ID, please verify the vCenter in question was indeed running vCenter 9.0 or later.
10. Change your API endpoint to "cis".
11. Expand "tasks".
12. Expand `/api/cis/tasks/{tasks}/{task}`.
13. Enter your task ID from step 9 into the task field and click "Execute".
14. Look at `vum_operations_enabled` under results. If this key is equal to `true`, VUM has been unrestricted. If the value is `false`, please examine the payload for answers as to why not.
