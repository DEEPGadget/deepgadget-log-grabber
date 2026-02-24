# deepgadget-log-grabber

Manycore 장비용 진단 로그 수집 스크립트입니다. 시스템 로그, 하드웨어 정보, GPU 데이터, 네트워크/서비스/모듈 설정 등을 단일 압축 아카이브로 수집해 지원 및 장애 분석에 활용합니다.

## 사용법

```bash
sudo bash deepgadget-log-grabber.sh [--short] [출력파일명]
```

| 인수 | 설명 |
|---|---|
| `--short` | `/etc` 설정과 `/var/log` 항목만 수집 (빠른 실행) |
| `출력파일명` | 생성될 아카이브 이름 (기본값: `Manycore-bug-report`) |

### 기본 실행

```bash
sudo bash deepgadget-log-grabber.sh
```

최초 실행 시 진단 도구 목록을 출력하고 설치 여부를 묻습니다.

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

`nvidia-bug-report.sh`, `smartctl`, `ipmitool`, `journalctl` 등 시간이 오래 걸리는 항목을 건너뛰고 `/etc` 설정과 `/var/log` 파일만 수집합니다.

### 환경변수로 도구 설치 제어

```bash
# 설치 프롬프트에 자동으로 Y 응답 (설치 허용)
SKIP_TOOLS=0 sudo bash deepgadget-log-grabber.sh

# 패키지 설치 없이 실행
SKIP_TOOLS=1 sudo bash deepgadget-log-grabber.sh
```

## 수집 결과물

실행 후 현재 디렉터리에 `<출력파일명>.tar.gz`가 생성됩니다. 아카이브 내부 구조는 다음과 같습니다.

### 전체 수집 항목

| 디렉터리 | 수집 내용 |
|---|---|
| `drives-and-storage/` | `lsblk`, SMART 데이터, `iostat`, `df`, `fstab`, `mdstat`, 마운트 정보, mdadm RAID |
| `system-logs/` | `dmesg`, `kern.log`, `syslog`, `dpkg.log`, `journalctl` (최근 30일), APT 히스토리, Slurm/Lustre 로그 |
| `repos-and-packages/` | `dpkg -l`, `pip list`, APT 소스 목록 |
| `networking/` | `netplan`, `ip addr`, `iptables`, `ufw`, `resolvectl`, `ss`, `/etc` 네트워킹 설정 |
| `gpu-memory-errors/` | ECC 오류 (corrected/uncorrected), 리매핑된 메모리 행 |
| `bmc-info/` | IPMI 이벤트 목록 (`sel elist`), 센서 데이터 (`sdr`) |
| `grub/` | `/proc/cmdline`, `/etc/default/grub`, `grub.d/` |
| `etc-config/services/` | systemd 설정 파일, 커스텀 유닛, init.d 목록, cron 작업 |
| `etc-config/modules/` | `/etc/modules`, `modules-load.d/`, `modprobe.d/` |
| `etc-config/slurm/` | `/etc/slurm/` 전체 (존재 시) |
| `etc-config/lustre/` | `/etc/lustre/` 전체 (존재 시) |
| *(루트)* | NVIDIA 버그 리포트, `nvidia-smi`, GPU 시리얼, `lshw`, `lsmod`, `sysctl`, `sensors`, `top`, 업타임, InfiniBand 상태, 절전 설정 |

### `--short` 모드 수집 항목

| 디렉터리 | 수집 내용 |
|---|---|
| `system-logs/` | `dmesg`, `kern.log`, `syslog`, `dpkg.log`, APT 히스토리, dmesg 에러, Slurm/Lustre 로그 |
| `networking/` | `/etc` 네트워킹 설정 (`hosts`, `resolv.conf`, `nsswitch.conf` 등) |
| `etc-config/services/` | systemd 설정, 커스텀 유닛, cron 작업 |
| `etc-config/modules/` | 모듈 로드 설정, modprobe 설정 |
| `etc-config/slurm/` | `/etc/slurm/` 전체 (존재 시) |
| `etc-config/lustre/` | `/etc/lustre/` 전체 (존재 시) |

## 선택적 의존 도구

스크립트 실행 시 아래 도구의 설치 여부를 확인하고, 없으면 설치를 제안합니다.

| 도구 | 패키지 | 가상 머신 |
|---|---|---|
| `smartctl` | `smartmontools` | 생략 |
| `ipmitool` | `ipmitool` | 생략 |
| `sensors` | `lm-sensors` | 생략 |
| `iostat` | `sysstat` | 수집 |
| `lshw` | `lshw` | 수집 |

가상 머신(QEMU) 환경에서는 `smartctl`, `ipmitool`, `sensors`를 설치 및 수집 대상에서 제외합니다.

## 참고 사항

- 대부분의 수집 명령에 `sudo` 권한이 필요합니다.
- NVIDIA 드라이버가 설치된 경우 `nvidia-bug-report.sh`를 실행합니다.
- 특정 도구나 데이터 소스를 사용할 수 없는 경우, 스크립트가 중단되지 않고 해당 파일에 안내 메시지를 남깁니다.
- 출력 아카이브에는 민감한 시스템 정보가 포함될 수 있습니다. 공유 전 내용을 확인하십시오.
- `/etc/NetworkManager/system-connections/`는 저장된 네트워크 자격증명 보호를 위해 수집하지 않습니다.

## 라이선스

BSD 3-Clause. [LICENSE](LICENSE) 참조.

NVIDIA의 `nvidia-bug-report.sh` 스크립트는 NVIDIA Corporation의 자산으로, 출처를 명시하여 사용합니다.
