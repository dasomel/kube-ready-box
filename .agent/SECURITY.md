# Security Policy

## Security Principles

### 1. Secure by Default

All configurations must be secure by default. Even for testing purposes, insecure default values should not be used.

**Reason**: To prevent test configurations from being used directly in production.

### 2. SSH Key Management

- Use `insert_key = true` (Vagrant default)
- Vagrant insecure key is used only for initial access
- Automatically replaced with a new secure key when VM is created

```ruby
# Vagrantfile
config.ssh.insert_key = true  # Enable automatic secure key replacement
```

### 3. Vagrant Insecure Key

The `packer/keys/vagrant` file is the [HashiCorp official insecure key](https://github.com/hashicorp/vagrant/tree/main/keys).

- Used only for initial SSH access during build
- Automatically replaced with a new key in deployed boxes
- Never use insecure key directly in production environments

### 4. Password Authentication

- Use password authentication only during build/testing
- Recommend disabling password authentication for production deployment

### 5. Network Configuration

- Use private network when possible
- Restrict access with firewall rules when using public network
- Expose only necessary service ports
- Isolate vulnerable VMs from host network

```ruby
# Private network recommended
config.vm.network "private_network", ip: "192.168.56.10"
```

### 6. Shared Folders

- Disable shared folders if not needed
- Shared folders can be an attack vector to the host system

```ruby
# Disable shared folder
config.vm.synced_folder ".", "/vagrant", disabled: true
```

### 7. Sensitive Data

- Never hardcode API keys, passwords, or other sensitive information in Vagrantfile
- Use environment variables or encrypted files
- Add sensitive files to `.gitignore`

### 8. Minimize Attack Surface

- Install only necessary packages
- Disable or remove unused services
- Apply regular security updates

### 9. SSH Configuration

- `~/.ssh` directory: `0700` permissions
- `~/.ssh/authorized_keys`: `0600` permissions
- Consider changing default SSH port (22) to reduce brute-force attacks

### 10. Box Updates

- Use boxes only from trusted sources
- Regularly update Vagrant and providers (VirtualBox, VMware)
- Apply patches for known vulnerabilities

### 11. OS Kernel Security Hardening (CIS Benchmark)

Kernel security settings applied to the Box:

| Setting | Value | Purpose |
|---------|-------|---------|
| `net.ipv4.conf.all.rp_filter` | 1 | Prevent IP Spoofing |
| `net.ipv4.conf.all.accept_redirects` | 0 | Block ICMP Redirect (MITM prevention) |
| `net.ipv4.conf.all.send_redirects` | 0 | Block ICMP Redirect sending |
| `net.ipv4.conf.all.accept_source_route` | 0 | Block Source Routing |
| `net.ipv4.tcp_syncookies` | 1 | Prevent SYN Flood attacks |
| `net.ipv4.icmp_echo_ignore_broadcasts` | 1 | Prevent Smurf attacks |
| `net.ipv4.icmp_ignore_bogus_error_responses` | 1 | Ignore bogus ICMP responses |
| `net.ipv4.conf.all.log_martians` | 1 | Log Martian packets |
| `net.ipv6.conf.all.disable_ipv6` | 1 | Disable IPv6 |

### 12. SSH Hardening

- `PermitRootLogin no` - Block root SSH access
- `PasswordAuthentication yes` - For build only (recommend no for production)
- `PubkeyAuthentication yes` - Enable public key authentication

## Reporting Security Issues

If you find a security vulnerability, please report it via Issue.

## References

- [HashiCorp - Creating a Base Box](https://developer.hashicorp.com/vagrant/docs/boxes/base)
- [Securing Vagrant Environments - Reintech](https://reintech.io/blog/securing-vagrant-environments-developer-best-practices)
- [DevSecOps Guides - Attacking Vagrant](https://blog.devsecopsguides.com/p/attacking-vagrant)
- [CIS Kubernetes Benchmarks](https://www.cisecurity.org/benchmark/kubernetes)
- [Hardening Kubernetes Nodes on Ubuntu](https://schoenwald.aero/posts/2025-03-09_hardening-kubernetes-nodes-on-ubuntu/)
- [K3s CIS Hardening Guide](https://docs.k3s.io/security/hardening-guide)
