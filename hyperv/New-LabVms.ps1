#Requires -RunAsAdministrator
<#
    Creates the three lab VMs and attaches the Rocky Linux install ISO.
    Safe to re-run: VMs that already exist are skipped.
#>
param(
    [string]$IsoPath  = 'D:\Projects\Kubernetes cluster\.iso\Rocky-9-latest-x86_64-minimal.iso',
    [string]$VmRoot   = 'D:\Hyper-V',
    [string]$SwitchName = 'k8s-lab'
)

if (-not (Test-Path $IsoPath)) { throw "ISO not found at $IsoPath" }
if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
    throw "Switch '$SwitchName' not found. Run New-LabSwitch.ps1 first."
}

# 2 vCPU / 4 GB / 40 GB each. Three nodes = 6 vCPU and 12 GB of your 32 GB.
$Nodes = @(
    @{ Name = 'k8s-cp1'; Memory = 4GB; Cpu = 2; Disk = 40GB }
    @{ Name = 'k8s-w1';  Memory = 4GB; Cpu = 2; Disk = 40GB }
    @{ Name = 'k8s-w2';  Memory = 4GB; Cpu = 2; Disk = 40GB }
)

New-Item -ItemType Directory -Path $VmRoot -Force | Out-Null

foreach ($n in $Nodes) {
    if (Get-VM -Name $n.Name -ErrorAction SilentlyContinue) {
        "Skipping $($n.Name) - already exists"
        continue
    }

    $vhd = Join-Path $VmRoot "$($n.Name).vhdx"

    New-VM -Name $n.Name -Generation 2 -MemoryStartupBytes $n.Memory `
           -NewVHDPath $vhd -NewVHDSizeBytes $n.Disk `
           -SwitchName $SwitchName -Path $VmRoot | Out-Null

    Set-VMProcessor    -VMName $n.Name -Count $n.Cpu
    # Static memory: dynamic memory makes kubelet's resource accounting lie to you.
    Set-VMMemory       -VMName $n.Name -DynamicMemoryEnabled $false
    # Rocky's shim works with the MS UEFI CA template, but disabling Secure Boot
    # removes a whole class of confusing boot failures from a first lab build.
    Set-VMFirmware     -VMName $n.Name -EnableSecureBoot Off
    # Automatic checkpoints silently eat disk and confuse cluster state.
    Set-VM             -VMName $n.Name -AutomaticCheckpointsEnabled $false `
                       -AutomaticStartAction Nothing -AutomaticStopAction ShutDown

    Add-VMDvdDrive     -VMName $n.Name -Path $IsoPath
    $dvd = Get-VMDvdDrive -VMName $n.Name
    Set-VMFirmware     -VMName $n.Name -FirstBootDevice $dvd

    "Created $($n.Name)  ($($n.Cpu) vCPU, $($n.Memory/1GB) GB RAM, $($n.Disk/1GB) GB disk)"
}

""
Get-VM | Where-Object Name -like 'k8s-*' | Select-Object Name,State,ProcessorCount,MemoryStartup | Format-Table -AutoSize
"Start one with:  Start-VM k8s-cp1   then connect with:  vmconnect localhost k8s-cp1"
