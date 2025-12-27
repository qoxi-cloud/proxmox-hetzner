# Network Bridge Modes

Understanding the different network configurations available for your Proxmox installation.

## Overview

The installer offers three network bridge modes, each suited for different use cases:

| Mode | Bridge(s) | Best For |
|------|-----------|----------|
| **Internal NAT** | `vmbr0` (NAT) | Isolated VMs, single public IP |
| **External** | `vmbr0` (bridged) | Additional public IPs, direct VM access |
| **Both** | `vmbr0` (external) + `vmbr1` (NAT) | Maximum flexibility |

## Internal NAT (Default)

```
Internet
    │
    ▼
┌─────────────────────────────┐
│  Proxmox Host               │
│  Public IP: x.x.x.x         │
│                             │
│  ┌─────────────────────┐    │
│  │ vmbr0 (NAT bridge)  │    │
│  │ 10.0.0.1/24         │    │
│  └──────┬──────────────┘    │
│         │                   │
│    ┌────┴────┐              │
│    ▼         ▼              │
│  ┌───┐     ┌───┐            │
│  │VM1│     │VM2│            │
│  │.10│     │.20│            │
│  └───┘     └───┘            │
└─────────────────────────────┘
```

**Configuration:**
- `vmbr0` = NAT bridge with private subnet (default: `10.0.0.0/24`)
- VMs get private IPs (e.g., `10.0.0.10`, `10.0.0.20`)
- Host performs NAT for outbound traffic
- Use port forwarding for inbound access to VMs

**Use cases:**
- Single public IP from your provider
- VMs don't need direct internet exposure
- Network isolation between VMs and internet

**Port forwarding example (nftables):**
```bash
# Add to /etc/nftables.conf in nat table
nft add rule inet nat prerouting tcp dport 80 dnat to 10.0.0.10:80
```

## External (Bridged)

```
Internet
    │
    ▼
┌─────────────────────────────┐
│  Proxmox Host               │
│  Public IP: x.x.x.x         │
│                             │
│  ┌─────────────────────┐    │
│  │ vmbr0 (bridged)     │    │
│  │ bridge to eth0      │    │
│  └──────┬──────────────┘    │
│         │                   │
│    ┌────┴────┐              │
│    ▼         ▼              │
│  ┌───┐     ┌───┐            │
│  │VM1│     │VM2│            │
│  │pub│     │pub│            │
│  └───┘     └───┘            │
└─────────────────────────────┘
```

**Configuration:**
- `vmbr0` = bridged directly to physical NIC
- VMs can get public IPs
- Direct internet connectivity for VMs

**Use cases:**
- Additional public IPs from your provider
- VMs need direct internet access with public IPs
- Running services that require direct connectivity

**Requirements:**
- Additional IP addresses or subnets from provider
- Proper MAC address configuration (some providers require this)

## Both (Internal + External)

```
Internet
    │
    ▼
┌───────────────────────────────────────┐
│  Proxmox Host                         │
│  Public IP: x.x.x.x                   │
│                                       │
│  ┌─────────────┐   ┌─────────────┐    │
│  │ vmbr0       │   │ vmbr1       │    │
│  │ (external)  │   │ (NAT)       │    │
│  │ bridged     │   │ 10.0.0.1/24 │    │
│  └──────┬──────┘   └──────┬──────┘    │
│         │                 │           │
│    ┌────┴────┐       ┌────┴────┐      │
│    ▼         ▼       ▼         ▼      │
│  ┌───┐     ┌───┐   ┌───┐     ┌───┐    │
│  │VM1│     │VM2│   │VM3│     │VM4│    │
│  │pub│     │pub│   │.30│     │.40│    │
│  └───┘     └───┘   └───┘     └───┘    │
└───────────────────────────────────────┘
```

**Configuration:**
- `vmbr0` = bridged to physical NIC (external access)
- `vmbr1` = NAT bridge with private subnet (internal network)
- VMs can be connected to either or both bridges

**Use cases:**
- Maximum flexibility for different VM requirements
- Some VMs need public IPs, others need isolation
- Complex network topologies

## Choosing the Right Mode

| Scenario | Recommended Mode |
|----------|------------------|
| Single public IP, isolated VMs | Internal NAT |
| Multiple public IPs from provider | External |
| Mixed requirements | Both |
| Testing/development | Internal NAT |
| Production with multiple services | Both |

## Private Subnet Configuration

When using NAT (internal or both modes), you can customize the private subnet:

| Preset | Use Case |
|--------|----------|
| `10.0.0.0/24` | Default, Class A private |
| `192.168.1.0/24` | Home-style, Class C |
| `172.16.0.0/24` | Class B private |
| Custom | Any valid private CIDR |

The host uses `.1` address (e.g., `10.0.0.1`) as the gateway for VMs.

## MTU Configuration (Jumbo Frames)

Private bridges are configured with MTU 9000 (jumbo frames) by default for improved VM-to-VM performance:

| Bridge | MTU | Purpose |
|--------|-----|---------|
| vmbr0 (internal mode) | 9000 | VM-to-VM traffic optimization |
| vmbr1 (both mode) | 9000 | VM-to-VM traffic optimization |
| vmbr0 (external mode) | 1500 | Standard MTU for external network |

**Benefits of Jumbo Frames:**
- Reduced CPU overhead for large data transfers
- Higher throughput for VM-to-VM communication
- Better performance for storage traffic (NFS, iSCSI)

**Note:** External bridges use standard MTU (1500) since provider networks may not support jumbo frames. VMs on internal bridges should also configure MTU 9000 for optimal performance.

## IPv6 Configuration

The installer supports full dual-stack (IPv4 + IPv6) networking.

### IPv6 Modes

| Mode | Description |
|------|-------------|
| Auto | Automatically detect IPv6 from interface (default) |
| Manual | Manually specify IPv6 address and gateway |
| Disabled | IPv4-only configuration |

### IPv6 Network Layout

```
Internet (IPv4 + IPv6)
    │
    ▼
┌─────────────────────────────────────────┐
│  Proxmox Host                           │
│  IPv4: x.x.x.x/32                       │
│  IPv6: 2001:db8::1/128                  │
│  Gateway (IPv6): fe80::1                │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ vmbr0 (NAT bridge)              │    │
│  │ IPv4: 10.0.0.1/24               │    │
│  │ IPv6: 2001:db8:0:1::1/80        │    │
│  └──────────┬──────────────────────┘    │
│             │                           │
│        ┌────┴────┐                      │
│        ▼         ▼                      │
│      ┌───┐     ┌───┐                    │
│      │VM1│     │VM2│                    │
│      │.10│     │.20│                    │
│      └───┘     └───┘                    │
└─────────────────────────────────────────┘
```

### Default IPv6 Gateway

Most providers (including Hetzner) use link-local gateway `fe80::1` for IPv6 routing. This is the default value.

### Disabling IPv6

Select "Disabled" in the IPv6 menu during wizard configuration for IPv4-only setup.

---

**Next:** [Security](Security) | [Post-Installation](Post-Installation)
