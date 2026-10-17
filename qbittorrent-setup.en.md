# DVT qBittorrent Seeder & Tracker Setup Manual

Last updated: 2026-10-17 · [한국어](qbittorrent-setup.ko.md)

## Overview

In DVT, one qBittorrent PC acts as both the **seeder** (serves the source image) and the **embedded tracker** (brokers the peer list). Clients booted into WinPE download the image with aria2 and exchange pieces with each other.

- At 100 Mbps or slower, the **network bandwidth** is the bottleneck. The goal is to save seeder upload and let clients share pieces among themselves.
- At 1 Gbps or faster, the seeder's **disk, CPU and socket buffers** are the bottleneck. The goal is to raise buffers and I/O threads so the link stays full.

How to use: apply the common settings in section 2 first, pick your environment with section 5, then apply section 3 or 4 on top. Required items are those whose absence makes deployment fail or stall; recommended items improve stability and efficiency. Names follow the qBittorrent 5.x **English UI**: settings are under **Tools → Options**, torrent creation under **Tools → Torrent Creator**. Wording may differ slightly between versions. For the Korean UI, see the [Korean edition](qbittorrent-setup.ko.md) of this manual.

## Common settings (both environments)

Turn on the embedded tracker, lock the protocol to TCP, and create torrents in **V1 format**. aria2 supports neither μTP nor BitTorrent v2.

### Required

| Page | Setting | Value | Why |
| --- | --- | --- | --- |
| Advanced | Enable embedded tracker | Checked | qBittorrent acts as the tracker |
| Advanced | Embedded tracker port | 9000 (default) | Port used in the torrent's tracker URL |
| Connection | Peer connection protocol | TCP | aria2 does not support μTP |
| Connection | Port used for incoming connections | Fixed port (e.g. 6881) | Keeps firewall rules stable |
| BitTorrent | Torrent Queueing | Unchecked | Keeps the deployment torrent out of the queue |
| BitTorrent | Seeding Limits (ratio / seeding time) | All unchecked | Seeding must not stop mid-deployment |
| Torrent Creator | Torrent format | **V1** | aria2 cannot download V2 or Hybrid torrents |
| Torrent Creator | Optimize alignment | Unchecked | Padding files may appear on clients as real files |
| Torrent Creator | Tracker URLs | `http://<SEEDER_IP>:9000/announce` | Embedded tracker address; use the seeder's exact LAN IP |
| Torrent Creator | Start seeding immediately | Checked | Seeding starts as soon as the torrent is created |
| Torrent Creator | Piece size | See section 3 or 4 | Balances piece count and hashing load |

**Firewall (seeder PC, elevated Command Prompt)** — required

```
netsh advfirewall firewall add rule name="DVT qBittorrent tracker" dir=in action=allow protocol=TCP localport=9000
netsh advfirewall firewall add rule name="DVT qBittorrent peer" dir=in action=allow protocol=TCP localport=6881
```

If you change either port, change `localport` to match. Add these port rules even if a program-level rule exists, because a network on the Public profile can still be blocked.

### Recommended

| Page | Setting | Value | Why |
| --- | --- | --- | --- |
| Advanced | Network interface / Optional IP address to bind to | Deployment LAN adapter / seeder IP | Effectively required on multi-NIC seeders; prevents traffic leaving on the wrong network |
| Advanced | Enable port forwarding for embedded tracker | Unchecked | LAN only |
| Connection | Use UPnP / NAT-PMP port forwarding from my router | Unchecked | LAN only |
| BitTorrent | Enable DHT / Enable Peer Exchange (PeX) | Unchecked | Peers are found through the tracker; avoids outside exposure |
| BitTorrent | Enable Local Peer Discovery | Unchecked (if the tracker works) | Redundant with the tracker; a fallback when troubleshooting |
| BitTorrent | Encryption mode | Allow encryption | Compatible with aria2; forcing it costs CPU |
| BitTorrent | Enable anonymous mode | Unchecked | Peer identification is needed |
| Speed | Schedule the use of alternative rate limits | Unchecked | Prevents sudden slowdowns during deployment |
| Behavior | Power Management: Inhibit system sleep when torrents are seeding | Checked | Keeps the seeder awake during deployment |
| Torrent Creator | Private torrent | Checked | DHT and PeX stay off for this torrent regardless of global settings |

## 100 Mbps or slower

Keep seeder upload slots low so each peer completes pieces quickly and passes them on to other clients. A 100 Mbps link tops out around 12 MB/s, so with more than 10 clients the seeder alone drops to roughly 1 MB/s per client.

### Required

| Page | Setting | Value | Why |
| --- | --- | --- | --- |
| Connection | Maximum number of upload slots per torrent | 8 | Fewer slots mean faster per-peer speed and quicker piece completion for redistribution |
| Connection | Global maximum number of upload slots | 20 | Keeps the per-torrent slots from being capped globally |
| Torrent Creator | Piece size | 4 MiB | Smaller pieces let clients start exchanging sooner |

### Recommended

| Page | Setting | Value | Why |
| --- | --- | --- | --- |
| Speed | Global Rate Limits → Upload | 11000 KiB/s (about 90 Mbps) | Leaves headroom for remote management and tracker replies |
| Speed | Apply rate limit to peers on LAN | Checked when using the limit above | Otherwise LAN peers are not limited |
| Speed | Apply rate limit to transport overhead | Checked when using the limit above | Limits by actual link usage |
| Connection | Global maximum number of connections | 200 | Comfortably above the peer count |
| Connection | Maximum number of connections per torrent | 100 | |
| Advanced | Upload slots behavior | Fixed slots | Locks the slot count to the values above |
| Advanced | Upload choking algorithm | Round-robin | Spreads pieces evenly across clients |
| Advanced | Disk IO read mode | Enable OS cache | Fewer disk re-reads when the same piece goes to many peers |

Leave all other Advanced settings at their defaults. Disk and CPU are not the bottleneck here.

## 1 Gbps or faster

Remove all rate limits and raise upload slots, send buffers and disk I/O so the seeder fills the link. 1 Gbps is about 119 MB/s, which default send buffers and an HDD often cannot sustain.

### Required

| Area | Setting | Value | Why |
| --- | --- | --- | --- |
| Hardware | Image storage | SSD or faster (NVMe for 10 Gbps) | An HDD cannot keep up with random reads from many peers |
| Hardware | Seeder NIC and switch uplink | 1 Gbps or faster | A 100 Mbps uplink means a mixed network (section 5) |
| Speed | Global Rate Limits → Upload / Download | 0 (unlimited) | |
| Connection | Global maximum number of upload slots | Unchecked (unlimited) | Bandwidth allows sending to every peer at once |
| Connection | Maximum number of upload slots per torrent | 50 or unchecked | |
| Advanced | Send buffer watermark | 5120 KiB (default 500) | Prevents send buffer starvation on fast links |
| Advanced | Send buffer low watermark | 1024 KiB (default 10) | |
| Advanced | Send buffer watermark factor | 150 % (default 50) | |
| Torrent Creator | Piece size | 8 MiB (16 MiB for images over 50 GB) | Fewer pieces and less hashing load |

### Recommended

| Area | Setting | Value | Why |
| --- | --- | --- | --- |
| Hardware | Seeder RAM | 16 GB or more | Pieces stay in the OS cache, reducing disk reads |
| NIC properties | Energy Efficient Ethernet / Green Ethernet | Disabled | Reduces speed fluctuation during high-speed transfers |
| NIC properties | Jumbo Packet | Disabled (keep default) | Every WinPE driver and switch must support it, otherwise connections break |
| Connection | Global maximum number of connections | 500 | |
| Connection | Maximum number of connections per torrent | 300 | |
| Advanced | Upload choking algorithm | Round-robin | |
| Advanced | Asynchronous I/O threads | 16 (default 10) | More concurrent read requests |
| Advanced | Hashing threads | Half the CPU core count | Faster torrent creation and rechecks |
| Advanced | Physical memory (RAM) usage limit | 4096 MiB or more (to fit RAM) | Room for caching |
| Advanced | Disk queue size | 8192 KiB | Larger disk request queue |
| Advanced | Disk IO type | Default | If memory use is excessive, compare with POSIX-compliant (restart required) |
| Advanced | Disk IO read mode | Enable OS cache | Repeatedly requested pieces are served from RAM |
| Advanced | Socket backlog size | 100 (default 30) | Handles many clients connecting at once |
| Advanced | Outgoing connections per second | 50 (default 20) | |

## Choosing the environment and mixed networks

Pick the settings by the **slowest link on the path from the seeder to the switch**. Client speed only affects how fast clients exchange pieces with each other.

| Seeder path | Client links | Settings to apply | Note |
| --- | --- | --- | --- |
| 100 Mbps or slower | 100 Mbps or slower | Section 3 (100 Mbps or slower) | |
| 100 Mbps or slower | 1 Gbps or faster | Section 3 (100 Mbps or slower) | Fast client-to-client exchange greatly shortens total time |
| 1 Gbps or faster | 100 Mbps or slower | Section 4 (1 Gbps or faster) | Lower hardware demand; an HDD can work |
| 1 Gbps or faster | 1 Gbps or faster | Section 4 (1 Gbps or faster) | SSD required |

Check both the seeder NIC link speed (`ncpa.cpl` → adapter Status) and the switch uplink spec. The lower of the two decides.

## Pre-deployment checklist and troubleshooting

### Pre-deployment checklist

- [ ] The embedded tracker is on, and `netstat -an | find ":9000"` on the seeder shows LISTENING
- [ ] The firewall has inbound allow rules for the tracker port (9000) and peer port (6881)
- [ ] The torrent was created with Torrent format V1 and Optimize alignment unchecked
- [ ] The tracker URL IP matches the seeder's current LAN IP
- [ ] The torrent is Seeding, not Queued or Stopped
- [ ] The required items from section 3 or 4 are applied for your environment
- [ ] Sleep, screen saver and automatic update restarts on the seeder will not hit the deployment window

### Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| aria2 cannot open the torrent or reports a metadata error | V2 or Hybrid torrent | Recreate it with Torrent format set to V1 |
| Clients cannot reach the tracker | Firewall, wrong IP in the tracker URL, embedded tracker off | Rerun the firewall commands in section 2; check the tracker URL and Enable embedded tracker |
| A `.pad` folder or empty files appear on clients | Optimize alignment was on | Uncheck it and recreate the torrent |
| Seeder upload is 0 and no peers connect | Bound NIC or IP is not on the deployment network | Check Network interface and Optional IP address to bind to under Advanced |
| Stuck at tens of MB/s on 1 Gbps | Upload slot limits, default send buffers, HDD, LAN peer rate limit | Recheck section 4 values; move the image to an SSD |
| Every client downloads only from the seeder, never from each other | WinPE firewall blocks inbound client connections | Make sure the client script runs `wpeutil DisableFirewall` |
