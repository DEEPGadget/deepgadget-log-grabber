# deepgadget-log-grabber

<<<<<<< HEAD
deepgadget 서버 장애 진단을 위한 로그 수집 스크립트입니다. 시스템 로그, 하드웨어 정보, GPU 데이터, 네트워크/서비스/모듈 설정 등을 단일 압축 아카이브로 수집해 지원 및 장애 분석에 활용합니다.
=======
ManyCoreSoft의 deepgadget™ 서버에서 실행되는 진단용 로그 수집 스크립트입니다. 시스템 로그, GPU 정보, 하드웨어 데이터, 네트워크 설정 등을 수집하여 단일 압축 파일로 묶습니다.

---
>>>>>>> 549d65d (/var/log 하위 과거로그 수집, /etc 하위항목 수집)

## 사용법

```bash
<<<<<<< HEAD
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
=======
sudo bash deepgadget-log-grabber.sh [--detail] [output-name]
```

### 옵션

| 옵션 | 설명 |
|------|------|
| `--detail` | `/etc` 하위 전체 파일과 `/var/log`의 압축 아카이브 로그를 추가로 수집합니다. 민감한 정보가 포함될 수 있으므로 주의가 필요합니다. |
| `output-name` | 생성할 아카이브 파일의 이름을 지정합니다 (`.tar.gz` 확장자 제외). 지정하지 않을 경우 기본값은 `Manycore-bug-report`입니다. |

### 예시

```bash
# 기본 실행 → Manycore-bug-report.tar.gz 생성
sudo bash deepgadget-log-grabber.sh

# 파일명 지정 → deepgadget-A100-5.tar.gz 생성
sudo bash deepgadget-log-grabber.sh deepgadget-A100-5

# detail 모드와 파일명 함께 지정
sudo bash deepgadget-log-grabber.sh --detail deepgadget-A100-5
```

### 환경 변수

| 변수 | 설명 |
|------|------|
| `SKIP_TOOLS=0` | 진단 도구 설치 여부를 묻는 프롬프트에 자동으로 Y로 응답합니다. |

### 진단 도구 자동 설치

스크립트 실행 시 아래 도구가 없으면 설치 여부를 묻습니다. 가상 머신(QEMU)으로 감지된 경우 VM에서 유용하지 않은 도구(`smartmontools`, `ipmitool`, `lm-sensors`)는 건너뜁니다.

| 도구 | 패키지 | VM 생략 |
|------|--------|---------|
| `smartctl` | `smartmontools` | O |
| `ipmitool` | `ipmitool` | O |
| `sensors` | `lm-sensors` | O |
| `iostat` | `sysstat` | - |
| `lshw` | `lshw` | - |

---

## 수집 항목

실행 결과로 `Manycore-bug-report.tar.gz`가 생성됩니다. 수집 항목은 다음과 같습니다.

### GPU

| 파일 | 내용 |
|------|------|
| `nvidia-bug-report.log` | `nvidia-bug-report.sh` 전체 출력 |
| `nvidia-smi.txt` | `nvidia-smi` 출력 |
| `gpu-serials.txt` | GPU 시리얼 번호 및 버스 ID |
| `gpu-memory-errors/remapped-memory.txt` | GPU 리매핑된 메모리 행 데이터 |
| `gpu-memory-errors/ecc-errors.txt` | 수정된(correctable) ECC 오류 |
| `gpu-memory-errors/uncorrected-ecc_errors.txt` | 수정되지 않은(uncorrectable) ECC 오류 |

### 시스템 로그

| 파일 | 내용 |
|------|------|
| `system-logs/dmesg` | 커널 링 버퍼 로그 |
| `system-logs/kern.log` | 커널 로그 |
| `system-logs/syslog` | 시스템 로그 |
| `system-logs/dpkg.log` | dpkg 패키지 로그 |
| `system-logs/apt-history.log` | apt 설치 이력 전체 (버전순 병합) |
| `system-logs/dmesg-errors.txt` | 커널 오류 메시지만 필터링 |
| `system-logs/journalctl.txt` | `journalctl` 전체 출력 |
| `system-logs/var-log-archived/` | `--detail` 전용: `/var/log`의 압축 로그 파일 |

### 드라이브 및 스토리지

| 파일 | 내용 |
|------|------|
| `drives-and-storage/lsblk.txt` | 블록 장치 목록 및 마운트 정보 |
| `drives-and-storage/smartctl-<dev>.txt` | 드라이브별 SMART 데이터 |
| `drives-and-storage/iostat.txt` | I/O 통계 |
| `drives-and-storage/df.txt` | 파일시스템 디스크 사용량 |
| `drives-and-storage/fstab.txt` | `/etc/fstab` 파일시스템 테이블 |
| `drives-and-storage/mounts.txt` | `/proc/mounts` 현재 마운트 목록 |
| `drives-and-storage/mdstat.txt` | 소프트웨어 RAID 상태 |
| `drives-and-storage/mdadm-scan.txt` | mdadm 스캔 결과 (mdadm 존재 시) |
| `drives-and-storage/mdadm-conf.txt` | `/etc/mdadm/mdadm.conf` (mdadm 존재 시) |

### 네트워킹

| 파일 | 내용 |
|------|------|
| `networking/ip-addr.txt` | 네트워크 인터페이스 및 IP 정보 |
| `networking/netplan.txt` | Netplan 설정 |
| `networking/iptables.txt` | iptables 방화벽 규칙 |
| `networking/ufw-status.txt` | UFW 방화벽 상태 |
| `networking/resolvectl-status.txt` | DNS 리졸버 상태 |
| `networking/ss.txt` | 열린 TCP/UDP 소켓 목록 |
| `ibstat.txt` | InfiniBand 상태 (지원 시) |

### BMC / IPMI

| 파일 | 내용 |
|------|------|
| `bmc-info/ipmi-elist.txt` | IPMI 이벤트 로그 (지원 시) |
| `bmc-info/ipmi-sdr.txt` | IPMI 센서 데이터 (지원 시) |

### 부트 및 커널

| 파일 | 내용 |
|------|------|
| `grub/proc_cmdline.txt` | 현재 커널 부팅 파라미터 |
| `grub/grub.txt` | `/etc/default/grub` 설정 |
| `grub/grub.d/` | `/etc/default/grub.d/` 추가 설정 (존재 시) |
| `hibernation-settings.txt` | 절전/최대 절전 관련 systemd 타겟 상태 |

### 패키지 및 저장소

| 파일 | 내용 |
|------|------|
| `repos-and-packages/dpkg.txt` | 설치된 Debian 패키지 목록 |
| `repos-and-packages/pip-list.txt` | 설치된 Python 패키지 목록 |
| `repos-and-packages/sources-list.txt` | `/etc/apt/sources.list` (주석 제외) |
| `repos-and-packages/listd-repos.txt` | `/etc/apt/sources.list.d/` 저장소 항목 |

### 기타 시스템 정보

| 파일 | 내용 |
|------|------|
| `hw-list.txt` | 전체 하드웨어 목록 (`lshw`) |
| `lsmod.txt` | 로드된 커널 모듈 |
| `sysctl-all.txt` | 전체 sysctl 파라미터 |
| `systemctl-services.txt` | 실행 중인 systemd 서비스 목록 |
| `sensors.txt` | 하드웨어 온도/전압 센서 수치 |
| `top.txt` | 프로세스 스냅샷 |
| `uptime.txt` | 시스템 가동 시간 |

### --detail 전용 추가 수집 항목

| 항목 | 내용 |
|------|------|
| `etc-snapshot/` | `/etc` 하위 파일 전체 복사본 (민감 파일 제외, 아래 참고) |
| `system-logs/var-log-archived/` | `/var/log` 하위 압축 로그 파일 (`.gz`, `.bz2`, `.xz`, `.zst`) |

---

## Disclaimer

`Manycore-bug-report.tar.gz`를 Manycore에 전달함으로써, 출력물에 민감한 정보가 의도치 않게 포함될 수 있음을 인지하고 동의하는 것으로 간주됩니다. Manycore는 해당 출력물을 신고된 문제 조사 목적으로만 사용합니다.

`--detail` 모드 사용 시 아래의 민감한 파일 및 디렉터리는 `/etc` 스냅샷에서 **명시적으로 제외**됩니다:

| 제외 항목 | 이유 |
|-----------|------|
| `shadow`, `shadow-`, `gshadow`, `gshadow-` | 패스워드 해시 |
| `ssh_host_*_key` | SSH 호스트 개인 키 |
| `/etc/ssl/private/` | SSL/TLS 개인 키 |
| `/etc/kubernetes/` | Kubernetes 자격 증명 |
| `/etc/credstore/`, `/etc/credstore.encrypted/` | 자격 증명 저장소 |

Manycore 지원팀에 파일을 전달하기 전에 아카이브 내용을 반드시 검토하시기 바랍니다.

---

## 라이선스

Copyright 2024 Manycore, Inc. — BSD 3-Clause License

자세한 내용은 [LICENSE](LICENSE)를 참조하세요.

NVIDIA 버그 리포트 기능(`nvidia-bug-report.sh`) 크레딧: NVIDIA Corporation.
>>>>>>> 549d65d (/var/log 하위 과거로그 수집, /etc 하위항목 수집)
