# deepgadget-log-grabber

ManyCoreSoft의 [deepgadget™](https://deepgadget.com/?gad_source=1&gad_campaignid=21910801199&gbraid=0AAAAACuhlghMHVb4ueRS8l5xPomTykbPD&gclid=CjwKCAjwyMnNBhBNEiwA-Kcgu2IryHkwVrzFCqf4Hpo7YGh86wjPO75SuMI8W4a0JoHbLsKL-0TZzRoCDbcQAvD_BwE&lang=ko) 서버에서 실행되는 진단용 로그 수집 스크립트입니다. 시스템 로그, GPU 정보, 하드웨어 데이터, 네트워크 설정 등을 수집하여 단일 압축 파일로 생성합니다.

---

## 지원 운영체제

패키지 관리자를 자동으로 감지하여 OS에 맞는 항목을 수집합니다.

| 계열 | 배포판 (검증 버전) | 패키지 관리자 |
|---|---|---|
| Debian 계열 | Ubuntu (24.04), Debian | `apt-get` |
| RHEL 계열 | Rocky Linux (8.9, 9.3), CentOS (7.9), AlmaLinux, RHEL | `dnf` / `yum` |

---

## 사용법

```bash
sudo bash deepgadget-log-grabber.sh [--short] [--detail] [출력파일명]
```

| 인수 | 설명 |
|---|---|
| `--short` | `/etc` 설정과 `/var/log` 기본 로그만 수집. 외부 도구 설치 프롬프트 생략 (도구 설치 안 함). |
| `--detail` | 기본 수집에 더해 `/etc` 전체 스냅샷과 `/var/log` 과거(로테이트) 로그를 추가 수집. |
| `출력파일명` | 생성될 아카이브 이름 (기본값: `Manycore-bug-report`). `.tar.gz` 자동 추가. |

### 기본 실행

```bash
sudo bash deepgadget-log-grabber.sh
```

실행할 때마다 진단 도구 목록을 출력하고 설치 여부를 묻습니다. `Y`를 누르면 누락된 도구를 설치하고, 그 외 키를 누르면 설치 없이 진행합니다. (`--short` 모드 또는 `SKIP_TOOLS` 지정 시 생략)

### 출력 파일명 지정

```bash
sudo bash deepgadget-log-grabber.sh ticket-12345
# → ticket-12345.tar.gz 생성
```

### 빠른 수집 (`--short` 모드)

```bash
sudo bash deepgadget-log-grabber.sh --short
sudo bash deepgadget-log-grabber.sh --short ticket-12345
```

`nvidia-bug-report.sh`, `smartctl`, `ipmitool`, `journalctl` 등 시간이 오래 걸리는 항목을 건너뜁니다. 도구 설치 프롬프트도 자동으로 생략됩니다.

### 상세 수집 (`--detail` 모드)

```bash
sudo bash deepgadget-log-grabber.sh --detail
sudo bash deepgadget-log-grabber.sh --detail deepgadget-A100-5
```

기본 수집 항목 외에 `/etc` 전체 파일 스냅샷과 `/var/log` 내 과거 로그(`.gz`, `.bz2`, `.xz`, `.zst`, RHEL 계열의 `-YYYYMMDD` 형식)를 추가 수집합니다. 민감한 정보가 포함될 수 있으므로 공유 전 내용을 반드시 검토하십시오.

### 환경변수로 도구 설치 제어

```bash
# 설치 프롬프트에 자동으로 Y 응답 (설치 허용)
sudo SKIP_TOOLS=0 bash deepgadget-log-grabber.sh

# 프롬프트 없이 패키지 설치 없이 실행
sudo SKIP_TOOLS=1 bash deepgadget-log-grabber.sh
```

> `SKIP_TOOLS`는 반드시 `sudo` **뒤에** 지정하십시오. `SKIP_TOOLS=0 sudo bash ...` 형식은 sudo의 환경변수 초기화(`env_reset`)로 값이 전달되지 않아 프롬프트가 그대로 표시됩니다.
> `--short` 모드에서는 `SKIP_TOOLS` 값과 관계없이 도구를 설치하지 않습니다.

### 옵션 처리 규칙

- 옵션 순서는 무관합니다. 지원하지 않는 `--` 옵션은 무시됩니다.
- 출력파일명을 여러 개 지정하면 마지막 값이 사용됩니다.
- `--short`와 `--detail`을 함께 지정하면 공통 항목과 `--detail` 전용 항목만 수집합니다. (기본 모드 추가 항목 제외)

---

## 수집 결과물

실행 후 현재 디렉터리에 `<출력파일명>.tar.gz`가 생성됩니다.

### 항상 수집되는 항목 (모든 모드 공통)

| 경로 | 수집 내용 |
|---|---|
| `system-logs/dmesg`, `kern.log`, `syslog`, `dpkg.log` | `/var/log` 동일 파일 (Debian 계열) |
| `system-logs/apt-history.log` | APT 설치 이력 전체 (`/var/log/apt/history.log*` 버전순 병합, Debian 계열) |
| `system-logs/messages`, `boot.log`, `dnf.log`, `dnf.rpm.log`, `yum.log` | `/var/log` 동일 파일 (RHEL 계열, 존재 시) |
| `system-logs/dnf-history.txt` 또는 `yum-history.txt` | `dnf history list` / `yum history list` (RHEL 계열) |
| `system-logs/dmesg-errors.txt` | 커널 오류 메시지만 필터링 (`dmesg -Tl err`) |
| `system-logs/slurm/` | `/var/log/slurm/` 전체 (존재 시) |
| `system-logs/lustre/` | `/var/log/lustre/` 전체 (존재 시) |
| `networking/` | `/etc/hosts`, `hostname`, `resolv.conf`, `nsswitch.conf`, `hosts.allow`, `hosts.deny`, `nftables.conf`, `/etc/network/`, `NetworkManager.conf`, systemd 네트워크 파일 (`*.network`, `*.netdev`, `*.link`) |
| `networking/sysconfig-network-scripts/` | `/etc/sysconfig/network-scripts/ifcfg-*` (RHEL 계열, `keys-*` 제외) |
| `networking/etc-sysconfig-network.txt` | `/etc/sysconfig/network` (RHEL 계열) |
| `etc-config/selinux-config.txt` | `/etc/selinux/config` (존재 시) |
| `etc-config/services/` | systemd 설정(`system.conf`, `journald.conf` 등), `/etc/systemd/system/` 유닛 파일, `init.d` 목록, `crontab`, `cron.d/daily/hourly/weekly/monthly` |
| `etc-config/modules/` | `/etc/modules`, `modules-load.d/`, `modprobe.d/` |
| `etc-config/slurm/` | `/etc/slurm/` 전체 (존재 시) |
| `etc-config/lustre/` | `/etc/lustre/` 전체 (존재 시) |

### 기본·상세 모드에서 추가 수집되는 항목 (`--short` 제외)

| 경로 | 수집 내용 |
|---|---|
| `nvidia-bug-report.log` | `nvidia-bug-report.sh` 전체 출력 |
| `nvidia-smi.txt` | `nvidia-smi` 출력 |
| `gpu-serials.txt` | GPU 시리얼 번호 및 버스 ID |
| `gpu-memory-errors/remapped-memory.txt` | GPU 리매핑된 메모리 행 |
| `gpu-memory-errors/ecc-errors.txt` | corrected ECC 오류 |
| `gpu-memory-errors/uncorrected-ecc_errors.txt` | uncorrected ECC 오류 |
| `system-logs/journalctl.txt` | `journalctl` 최근 30일 |
| `ibstat.txt` | InfiniBand 상태 (지원 시) |
| `bmc-info/ipmi-elist.txt` | IPMI 이벤트 로그 (지원 시) |
| `bmc-info/ipmi-sdr.txt` | IPMI 센서 데이터 (지원 시) |
| `sensors.txt` | 하드웨어 온도/전압 센서 수치 |
| `hw-list.txt` | 전체 하드웨어 목록 (`lshw`) |
| `lsmod.txt` | 로드된 커널 모듈 |
| `sysctl-all.txt` | 전체 sysctl 파라미터 |
| `systemctl-services.txt` | systemd 서비스 목록 |
| `top.txt` | 프로세스 스냅샷 |
| `uptime.txt` | 시스템 가동 시간 |
| `hibernation-settings.txt` | 절전/최대 절전 관련 systemd 타겟 상태 |
| `drives-and-storage/lsblk.txt` | 블록 장치 목록 |
| `drives-and-storage/smartctl-<dev>.txt` | 드라이브별 SMART 데이터 |
| `drives-and-storage/iostat.txt` | I/O 통계 |
| `drives-and-storage/df.txt` | 파일시스템 디스크 사용량 |
| `drives-and-storage/fstab.txt` | `/etc/fstab` |
| `drives-and-storage/mounts.txt` | `/proc/mounts` 현재 마운트 목록 |
| `drives-and-storage/mdstat.txt` | 소프트웨어 RAID 상태 |
| `drives-and-storage/mdadm-scan.txt` | mdadm 스캔 결과 (mdadm 존재 시) |
| `drives-and-storage/mdadm-conf.txt` | `/etc/mdadm/mdadm.conf` 또는 `/etc/mdadm.conf` (mdadm 존재 시) |
| `grub/proc_cmdline.txt` | 현재 커널 부팅 파라미터 |
| `grub/grub.txt` | `/etc/default/grub` |
| `grub/grubby.txt` | `grubby --info=ALL` 부트 항목 (RHEL 계열) |
| `grub/grub.d/` | `/etc/default/grub.d/` 추가 설정 (존재 시) |
| `repos-and-packages/dpkg.txt` | 설치된 Debian 패키지 목록 (Debian 계열) |
| `repos-and-packages/sources-list.txt` | `/etc/apt/sources.list` (주석 제외, Debian 계열) |
| `repos-and-packages/listd-repos.txt` | `/etc/apt/sources.list.d/` 저장소 항목 (Debian 계열) |
| `repos-and-packages/rpm.txt` | 설치된 RPM 패키지 목록 및 설치 일시 (RHEL 계열) |
| `repos-and-packages/yum-repos.txt` | `/etc/yum.repos.d/*.repo` (주석 제외, RHEL 계열) |
| `repos-and-packages/repolist.txt` | `dnf/yum repolist all` (RHEL 계열) |
| `repos-and-packages/pip-list.txt` | 설치된 Python 패키지 목록 (`pip` 또는 `pip3`) |
| `networking/netplan.txt` | Netplan 설정 (netplan 존재 시) |
| `networking/nmcli.txt` | NetworkManager 상태 및 연결 목록 (nmcli 존재 시, 비밀번호 미포함) |
| `networking/ip-addr.txt` | 네트워크 인터페이스 및 IP 정보 |
| `networking/iptables.txt` | iptables 방화벽 규칙 |
| `networking/ufw-status.txt` | UFW 방화벽 상태 (ufw 존재 시) |
| `networking/firewalld.txt` | firewalld 상태 및 전체 zone 설정 (firewall-cmd 존재 시) |
| `networking/nft-ruleset.txt` | nftables 규칙 (nft 존재 시) |
| `selinux-status.txt` | SELinux 상태 (sestatus 존재 시) |
| `networking/resolvectl-status.txt` | DNS 리졸버 상태 |
| `networking/ss.txt` | 열린 TCP/UDP 소켓 목록 |

### `--detail` 모드에서만 추가 수집되는 항목

| 경로 | 수집 내용 |
|---|---|
| `etc-snapshot/` | `/etc` 하위 파일 전체 복사본 (민감 파일 제외, 아래 참고) |
| `system-logs/var-log-archived/` | `/var/log` 하위 과거 로그 파일 (`.gz`, `.bz2`, `.xz`, `.zst`, RHEL 계열 `-YYYYMMDD`) |

---

## 선택적 의존 도구

스크립트 실행 시 아래 도구의 설치 여부를 확인하고, 없으면 설치를 제안합니다 (`--short` 모드 제외).

| 도구 | 패키지 (Debian 계열) | 패키지 (RHEL 계열) | 가상 머신(QEMU) |
|---|---|---|---|
| `smartctl` | `smartmontools` | `smartmontools` | 설치·수집 생략 |
| `ipmitool` | `ipmitool` | `ipmitool` | 설치·수집 생략 |
| `sensors` | `lm-sensors` | `lm_sensors` | 설치·수집 생략 |
| `iostat` | `sysstat` | `sysstat` | 정상 수집 |
| `lshw` | `lshw` | `lshw` | 정상 수집 |

설치는 감지된 패키지 관리자(`apt-get` / `dnf` / `yum`)로 진행됩니다. 저장소에 패키지가 없어 설치에 실패하면 안내 문구를 출력하고 해당 도구 없이 계속 진행합니다.

---

## Disclaimer

`<출력파일명>.tar.gz`를 ManyCoreSoft에 전달함으로써, 출력물에 민감한 정보가 의도치 않게 포함될 수 있음을 인지하고 동의하는 것으로 간주됩니다. ManyCoreSoft는 해당 출력물을 신고된 문제 조사 목적으로만 사용합니다.

`--detail` 모드 사용 시 아래 파일 및 디렉터리는 `/etc` 스냅샷에서 **명시적으로 제외**됩니다.

| 제외 항목 | 이유 |
|---|---|
| `shadow`, `shadow-`, `gshadow`, `gshadow-` | 패스워드 해시 |
| `ssh_host_*_key` | SSH 호스트 개인 키 |
| `/etc/ssl/private/` | SSL/TLS 개인 키 |
| `/etc/kubernetes/` | Kubernetes 자격 증명 |
| `/etc/credstore/`, `/etc/credstore.encrypted/` | 자격 증명 저장소 |
| `/etc/NetworkManager/system-connections/` | 저장된 Wi-Fi/VPN 자격 증명 |
| `/etc/sysconfig/network-scripts/keys-*` | 저장된 Wi-Fi/802.1x 자격 증명 (RHEL 계열) |

`/etc/NetworkManager/system-connections/`는 모든 모드에서 수집하지 않습니다.

위 목록 외의 `/etc` 파일(예: `/etc/slurm/slurmdbd.conf`, `/etc/munge/munge.key`, VPN 설정 등)은 `--detail` 모드에서 수집됩니다. 공유 전 내용을 검토하십시오.

---

## 참고 사항

- 대부분의 수집 명령에 `sudo` 권한이 필요합니다. `sudo`가 설치되지 않은 최소 설치(minimal) 환경에서는 root로 직접 실행하면 `sudo` 없이 동작합니다.
- 특정 도구나 데이터 소스를 사용할 수 없는 경우 스크립트가 중단되지 않고 해당 파일에 `No ... data available` 안내 메시지를 남깁니다.
- 설치 프롬프트는 터미널(`/dev/tty`)에서 입력을 받습니다. cron 등 비대화형 환경에서는 `--short` 또는 `sudo SKIP_TOOLS=0|1 ...`을 사용하고, 원격 실행 시 `ssh -t`를 사용하십시오.
- Windows에서 저장소를 받은 경우 스크립트가 CRLF 줄바꿈으로 변환될 수 있습니다. 서버에서 직접 `git clone` 하거나 `sed -i 's/\r$//' deepgadget-log-grabber.sh`로 변환 후 실행하십시오.
- 출력 아카이브를 ManyCoreSoft 지원팀에 전달하기 전에 내용을 반드시 검토하십시오.

---

## 라이선스

Copyright 2024 Manycore, Inc. — BSD 3-Clause License

자세한 내용은 [LICENSE](LICENSE)를 참조하세요.

NVIDIA 버그 리포트 기능(`nvidia-bug-report.sh`) 크레딧: NVIDIA Corporation.
