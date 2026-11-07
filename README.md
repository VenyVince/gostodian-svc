# gostodian-svc

홈랩에서 `gostodian-gate`가 허용된 동사만 넘기는 헬퍼다. 상주 프로세스가 아니다. 게이트가 한 번 실행하고, 그 동사가 끝나면 같이 종료된다.

계약은 [GOSTODIAN_SVC.md](https://github.com/team-croffle/gostodian/blob/master/GOSTODIAN_SVC.md)다. `status`와 `boot-id`는 이 헬퍼가 아니다. 게이트가 직접 읽는다.

## 설치

경로와 권한은 계약과 같다.

| 항목 | 값 |
|---|---|
| 경로 | `/usr/local/libexec/gostodian-svc` |
| 소유 | `root:root` |
| 권한 | `0755` |

```bash
sudo install -o root -g root -m 0755 gostodian-svc /usr/local/libexec/gostodian-svc
sudo touch /var/log/gostodian-svc.log
sudo chgrp gostodian /var/log/gostodian-svc.log
sudo chmod 0664 /var/log/gostodian-svc.log
```

`health`는 sudo 없이 점검 계정으로 돈다. 실패 이유는 `/var/log/gostodian-svc.log`에 붙인다. 점검 계정이 그 파일에 쓸 수 있어야 한다. 점검 계정은 도커 소켓을 읽을 수 있어야 하고, 그 계정에 `docker` 그룹을 주는 일은 홈랩 운영 준비다.

갱신 상태 파일은 `/run/gostodian/update-status`다. `update`가 root로 만들고, `update-status`가 점검 계정으로 읽는다.

## 표

서비스 이름, compose 경로, health가 볼 컨테이너와 포트는 헬퍼 안의 표다. 이 저장소에는 확인되지 않은 이름을 넣지 않는다. 홈랩에서 아래 줄을 채운 뒤에 `down`, `start`, `health`가 그 대상을 다룬다.

```
service|게이트이름|compose프로젝트|작업디렉터리|compose서비스|compose파일
container|컨테이너이름
port|포트
```

`compose파일`은 비울 수 있다. 비우면 작업 디렉터리의 기본 compose 파일을 쓴다.

`log` 줄은 계약에 적힌 보통 경로다. 홈랩의 파일 이름이 다르면 그 경로로 고친다. 회전본 패턴을 비우면 현재 파일 이름 뒤에 `-`가 붙은 파일을 이름 오름차순으로 읽고, 이어서 현재 파일을 읽는다.

```
log|dnf|/var/log/dnf.log|
log|boot|/var/log/boot.log|
log|secure|/var/log/secure|
log|fail2ban|/var/log/fail2ban.log|
```

게이트 허용 목록, 점검 머신의 `pipeline.docker_order`, 이 표의 게이트 이름은 같아야 한다. `health`의 컨테이너와 포트는 `start`로 올리는 집합과 같아야 한다.

## sudoers

`docker`, `dnf`, `systemd-run`은 sudoers에 없다. 헬퍼의 고정 인자만 올린다. 서비스마다 `down` 한 줄, `start` 한 줄이다.

```
gostodian ALL=(root) NOPASSWD: /usr/local/libexec/gostodian-svc down <서비스>
gostodian ALL=(root) NOPASSWD: /usr/local/libexec/gostodian-svc start <서비스>
gostodian ALL=(root) NOPASSWD: /usr/local/libexec/gostodian-svc update
gostodian ALL=(root) NOPASSWD: /usr/local/libexec/gostodian-svc reboot
gostodian ALL=(root) NOPASSWD: /usr/local/libexec/gostodian-svc collect-logs dnf
gostodian ALL=(root) NOPASSWD: /usr/local/libexec/gostodian-svc collect-logs boot
gostodian ALL=(root) NOPASSWD: /usr/local/libexec/gostodian-svc collect-logs secure
gostodian ALL=(root) NOPASSWD: /usr/local/libexec/gostodian-svc collect-logs fail2ban
```

`update-status`, `health`, `resources`는 sudo 없이 호출된다.

## 동사

| 인자 | 하는 일 | 끝 |
|---|---|---|
| `down <서비스>` | 표의 그 서비스만 `compose down` | 내려가 있거나 내리면 0, 실패하면 1 |
| `start <서비스>` | 표의 그 서비스만 `compose up -d` | 떠 있거나 뜨면 0, 실패하면 1 |
| `update` | `/run/gostodian/update-status`에 `running`을 쓰고 `gostodian-update` 유닛으로 `dnf -y update`를 시작한 뒤 반환 | 유닛을 만들면 0. 이미 돌고 있으면 파일을 바꾸지 않고 0. `systemd-run` 실패면 `failed`를 쓰고 1 |
| `update-status` | 상태 파일의 첫 단어를 stdout에 씀. `running`, `done`, `failed`만 그대로 두고 그 외는 `failed` | 항상 0 |
| `reboot` | `systemctl reboot` | 재부팅을 걸면 0 |
| `collect-logs <종류>` | `dnf`, `boot`, `secure`, `fail2ban` 중 하나. 회전본을 이름순으로, 이어서 현재 파일을 stdout에 이어 붙임. 각 파일 앞에 `# <절대경로>` | 하나라도 읽으면 0. 파일이 없거나 읽기 오류면 1 |
| `resources` | `RAM`, `CPU`, `Storage` | 하나라도 읽지 못하면 1 |
| `health` | 표의 컨테이너가 running인지, 표의 포트가 `ss -ltn`으로 Listening인지 | 모두 맞으면 한 줄씩 쓰고 0. 아니면 1이고 이유를 로컬 로그에 남김 |

알 수 없는 첫 인자, 인자가 더 있는 경우, 이름에 공백이 있는 경우는 아무것도 실행하지 않고 1로 끝난다. 표에 없는 서비스는 `down`과 `start`를 하지 않는다. 로그 파일은 지우지 않는다.

`update`가 만드는 유닛의 본명령은 `dnf -y update`다. `--wait`는 붙이지 않는다. `dnf`가 0으로 끝나면 유닛이 상태 파일을 `done`으로 덮고, 아니면 `failed`로 덮는다.

## 확인

```bash
make test
make check
```
