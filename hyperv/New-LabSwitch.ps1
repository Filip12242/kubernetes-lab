#Requires -RunAsAdministrator
<#
    Creates the lab network: an Internal Hyper-V switch plus a host-side NAT.

    Why Internal + NAT instead of the Default Switch:
    the Default Switch renumbers its subnet on every host reboot, which would
    break a cluster that has node IPs baked into its config. This gives us
    stable static IPs that survive reboots, and keeps the lab off the home LAN.

        host (vEthernet)  192.168.100.1
        k8s-cp1           192.168.100.11
        k8s-w1            192.168.100.12
        k8s-w2            192.168.100.13
#>

$SwitchName = 'k8s-lab'
$HostIP     = '192.168.100.1'
$PrefixLen  = 24
$NatName    = 'k8s-lab-nat'
$NatSubnet  = '192.168.100.0/24'

if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
    New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
    "Created switch $SwitchName"
} else {
    "Switch $SwitchName already exists"
}

$adapter = Get-NetAdapter -Name "vEthernet ($SwitchName)" -ErrorAction Stop
if (-not (Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $HostIP -ErrorAction SilentlyContinue)) {
    New-NetIPAddress -IPAddress $HostIP -PrefixLength $PrefixLen -InterfaceIndex $adapter.ifIndex | Out-Null
    "Assigned $HostIP/$PrefixLen to the host vNIC"
} else {
    "Host vNIC already has $HostIP"
}

if (-not (Get-NetNat -Name $NatName -ErrorAction SilentlyContinue)) {
    New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $NatSubnet | Out-Null
    "Created NAT $NatName for $NatSubnet"
} else {
    "NAT $NatName already exists"
}

""
"Done. Verify with: Get-VMSwitch; Get-NetNat"
