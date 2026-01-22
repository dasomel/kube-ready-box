---
name: license-check
description: Verify OSS license compliance, SPDX conformance, and legal requirements when reviewing LICENSE, NOTICE files, or discussing open source licensing for the project
---

# OSS License Compliance Check

Comprehensive license verification for open source projects, ensuring legal compliance and proper attribution.

## Instructions

When reviewing or creating license-related files, verify the following:

### 1. Required Files

Check that these files exist in the project root:

- **LICENSE** (or LICENSE.txt, LICENSE.md)
  - Contains full license text
  - Uses official SPDX license identifier
  - Includes copyright notice with year and owner

- **NOTICE** (or NOTICE.txt, NOTICE.md)
  - Lists all copyright holders
  - Attributes third-party components
  - Includes required legal notices from dependencies

- **README.md**
  - Contains license badge (e.g., MIT, Apache 2.0)
  - Links to LICENSE file
  - Brief license description in "License" section

### 2. License Selection Guidance

| License | Permissions | Conditions | Limitations | Best For |
|---------|-------------|------------|-------------|----------|
| MIT | Commercial use, Modification, Distribution, Private use | License and copyright notice | Liability, Warranty | Simple permissive license |
| Apache 2.0 | Commercial use, Modification, Distribution, Patent use, Private use | License and copyright notice, State changes | Trademark use, Liability, Warranty | Projects needing patent protection |
| GPL-3.0 | Commercial use, Modification, Distribution, Patent use, Private use | Disclose source, License and copyright notice, Same license, State changes | Liability, Warranty | Strong copyleft projects |
| BSD-3-Clause | Commercial use, Modification, Distribution, Private use | License and copyright notice | Liability, Warranty, Trademark use | Academic/research projects |

**Recommended for this project**: MIT or Apache 2.0 (permissive, enterprise-friendly)

### 3. SPDX Compliance

- **SPDX License Identifier**: Use in file headers
  ```bash
  # SPDX-License-Identifier: MIT
  # SPDX-FileCopyrightText: 2024 Your Name
  ```

- **Valid identifiers**: Check against https://spdx.org/licenses/
- **Multiple licenses**: Use SPDX expressions
  - AND: `Apache-2.0 AND MIT`
  - OR: `Apache-2.0 OR MIT`

### 4. Third-Party Component Attribution

#### Ubuntu Cloud Images (Base)
```
This project uses Ubuntu 24.04 Cloud Images:
- Source: https://cloud-images.ubuntu.com/
- License: Various (Ubuntu is primarily GPL, kernel is GPL-2.0)
- Attribution: Canonical Ltd.
```

#### Packer (Build Tool)
```
HashiCorp Packer:
- License: BUSL-1.1 (Business Source License)
- Note: Free for non-production use; check terms for commercial deployment
- https://github.com/hashicorp/packer
```

#### Vagrant (Distribution)
```
HashiCorp Vagrant:
- License: BUSL-1.1 (Business Source License)
- Note: Free for development; check terms for production use
- https://github.com/hashicorp/vagrant
```

#### Kubernetes Components (if included)
```
Kubernetes (kubeadm, kubelet, kubectl):
- License: Apache-2.0
- Copyright: The Kubernetes Authors
- https://github.com/kubernetes/kubernetes
```

#### Container Runtimes
```
containerd:
- License: Apache-2.0
- Copyright: The containerd Authors
- https://github.com/containerd/containerd

CRI-O (alternative):
- License: Apache-2.0
- Copyright: The CRI-O Authors
- https://github.com/cri-o/cri-o
```

### 5. NOTICE File Template

```
dasomel/ubuntu-24.04 Vagrant Box
Copyright 2024 [Your Name/Organization]

This product includes software developed by:

1. Canonical Ltd. (Ubuntu)
   - Ubuntu 24.04 Cloud Images
   - https://ubuntu.com/
   - Licenses: Various (primarily GPL)

2. HashiCorp (Packer, Vagrant)
   - https://www.hashicorp.com/
   - License: BUSL-1.1

3. The Kubernetes Authors (if K8s components included)
   - https://kubernetes.io/
   - License: Apache-2.0

4. [Add other components as needed]

For complete license texts, see the LICENSE file.
For third-party licenses, see the THIRD-PARTY-NOTICES file.
```

### 6. Legal Compliance Checks

#### Trademark Review
- [ ] No use of "Ubuntu" trademark in misleading way
- [ ] Proper attribution: "Based on Ubuntu 24.04"
- [ ] Check: https://ubuntu.com/legal/trademarks
- [ ] No use of "Kubernetes" logo without permission
- [ ] HashiCorp trademarks used appropriately

#### Patent Considerations
- [ ] Apache 2.0 includes patent grant (if used)
- [ ] No patent encumbrances in included code
- [ ] Document any known patent claims

#### Export Controls
- [ ] Check if cryptography requires export notification
- [ ] U.S. Export Administration Regulations (EAR) compliance
- [ ] Note: Standard SSH/TLS typically exempt

### 7. SBOM Generation (Software Bill of Materials)

Recommend generating SBOM for transparency:

```bash
# Using syft
syft packages dir:. -o spdx-json > sbom.spdx.json

# Using trivy
trivy fs --format spdx-json --output sbom.spdx.json .
```

Include in project:
- `sbom.spdx.json` - Machine-readable SBOM
- `THIRD-PARTY-NOTICES.md` - Human-readable component list

### 8. Review Checklist

When checking license compliance:

```
## File Existence
- [ ] LICENSE file present
- [ ] NOTICE file present
- [ ] README.md has license section
- [ ] License badge in README

## License Content
- [ ] Full license text included
- [ ] Copyright year current
- [ ] Copyright holder specified
- [ ] SPDX identifier present

## Third-Party Attribution
- [ ] All dependencies listed
- [ ] License compatibility verified
- [ ] Required notices included
- [ ] Source links provided

## Legal Compliance
- [ ] Trademark usage reviewed
- [ ] Patent grants considered
- [ ] Export controls checked
- [ ] SBOM generated (optional)
```

### 9. Output Format

Report findings as:

```
## CRITICAL Issues
- Missing LICENSE file
  Action: Create LICENSE with [recommended license]

## Warnings
- Incomplete NOTICE file
  Missing: containerd attribution
  Add: [attribution text]

## Recommendations
- Add license badge to README
  Badge: ![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
```

## Examples

### Example 1: Missing Attribution
```
## Warnings
- [NOTICE:15] Missing Ubuntu Cloud Images attribution
  Add:
  ```
  Ubuntu 24.04 Cloud Images
  Copyright Canonical Ltd.
  License: Various (https://ubuntu.com/legal)
  ```
```

### Example 2: Incompatible License
```
## CRITICAL Issues
- [scripts/helper.sh:1] GPL-3.0 code in permissive (MIT) project
  Issue: GPL requires derivative works to be GPL-licensed
  Options:
    1. Remove GPL code and reimplement
    2. Change project license to GPL-3.0
    3. Get permission to relicense component
```

### Example 3: Trademark Concern
```
## Warnings
- [README.md:5] Potential trademark issue
  Current: "Official Ubuntu Kubernetes Box"
  Fix: "Ubuntu 24.04-based Kubernetes Box" (removes "Official")
```

## Reference

- [Choose a License](https://choosealicense.com/)
- [SPDX License List](https://spdx.org/licenses/)
- [Ubuntu Legal](https://ubuntu.com/legal)
- [Kubernetes Trademark Guidelines](https://www.linuxfoundation.org/legal/trademark-usage)
- [Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0)
- [MIT License](https://opensource.org/licenses/MIT)
