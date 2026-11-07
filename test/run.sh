#!/bin/sh
# gostodian-svc 동작 확인. 서비스 이름은 픽스처일 뿐이고 홈랩 표가 아니다.
set -u

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
MOCK=$ROOT/test/mocks
PATH="$MOCK:/usr/bin:/bin"
export PATH

pass=0
fail=0

ok() {
	pass=$((pass + 1))
}

bad() {
	fail=$((fail + 1))
	printf 'FAIL %s\n' "$*" >&2
}

reset_env() {
	tmp=$(mktemp -d)
	export TMPD="$tmp"
	export DOCKER_LOG="$tmp/docker.log"
	export DOCKER_RC=0
	export DOCKER_STDERR=
	export DOCKER_STATE="$tmp/docker-state"
	export SYSTEMCTL_LOG="$tmp/systemctl.log"
	export SYSTEMCTL_ACTIVE=inactive
	export SYSTEMCTL_RC=0
	export SYSTEMD_RUN_LOG="$tmp/systemd-run.log"
	export SYSTEMD_RUN_RC=0
	export SS_FILE="$tmp/ss.txt"
	export SS_RC=0
	export NPROC_VALUE=2
	export NPROC_RC=0
	export DF_FILE="$tmp/df.txt"
	export DF_RC=0
	export DNF_LOG="$tmp/dnf.log"
	export G_TABLE_SET=1
	export G_TABLE=
	export G_STATUS="$tmp/status"
	export G_DIAG="$tmp/diag.log"
	export G_MEM="$tmp/meminfo"
	export G_LOAD="$tmp/loadavg"
	printf '%s\n' "State Recv-Q Send-Q Local Address:Port Peer Address:Port" >"$SS_FILE"
	printf '%s\n' "Filesystem Size Used Avail Use% Mounted on" "/dev/sda1 20G 10G 9.0G 53% /" >"$DF_FILE"
	printf '%s\n' "MemTotal:       1000 kB" "MemAvailable:    400 kB" >"$G_MEM"
	printf '%s\n' "0.01 0.02 0.03 1/2 3" >"$G_LOAD"
}

run_svc() {
	outf=$TMPD/stdout
	errf=$TMPD/stderr
	(
		# shellcheck disable=SC1091
		. "$ROOT/gostodian-svc"
		if [ "${G_TABLE_SET:-}" = 1 ]; then
			table=$G_TABLE
		fi
		status_file=$G_STATUS
		diag_log=$G_DIAG
		meminfo_path=$G_MEM
		loadavg_path=$G_LOAD
		main "$@"
	) >"$outf" 2>"$errf"
	code=$?
}

expect_code() {
	want=$1
	label=$2
	if [ "$code" -eq "$want" ]; then
		ok
	else
		bad "$label: exit $code want $want"
		printf 'stderr:\n%s\n' "$(cat "$errf")" >&2
	fi
}

expect_stdout() {
	label=$1
	shift
	printf '%s' "$*" >"$TMPD/want-out"
	if cmp -s "$TMPD/want-out" "$outf"; then
		ok
	else
		bad "$label: stdout mismatch"
		printf 'want:\n%s\nactual:\n%s\n' "$(cat "$TMPD/want-out")" "$(cat "$outf")" >&2
	fi
}

expect_stdout_file() {
	label=$1
	if cmp -s "$2" "$outf"; then
		ok
	else
		bad "$label: stdout mismatch"
		diff -u "$2" "$outf" >&2 || true
	fi
}

expect_file() {
	label=$1
	printf '%s' "$2" >"$TMPD/want-file"
	if [ -f "$3" ] && cmp -s "$TMPD/want-file" "$3"; then
		ok
	else
		bad "$label: file mismatch $3"
		if [ -f "$3" ]; then
			printf 'actual:\n%s\n' "$(cat "$3")" >&2
		else
			printf 'missing %s\n' "$3" >&2
		fi
	fi
}

diag_has() {
	label=$1
	needle=$2
	if [ -f "$G_DIAG" ] && grep -F -q -- "$needle" "$G_DIAG"; then
		ok
	else
		bad "$label: diag missing [$needle]"
		if [ -f "$G_DIAG" ]; then
			cat "$G_DIAG" >&2
		fi
	fi
}

no_file() {
	label=$1
	if [ ! -e "$2" ] || [ ! -s "$2" ]; then
		ok
	else
		bad "$label: unexpected $2"
		cat "$2" >&2 || true
	fi
}

# --- 인자 ---

reset_env
run_svc
expect_code 1 "no args"

reset_env
run_svc nosuch
expect_code 1 "unknown verb"
no_file "unknown verb does nothing" "$DOCKER_LOG"

reset_env
run_svc down
expect_code 1 "down without name"
no_file "down without name" "$DOCKER_LOG"

reset_env
G_TABLE="service|web|proj|$TMPD/work|web|"
mkdir -p "$TMPD/work"
run_svc down web extra
expect_code 1 "down extra arg"
no_file "down extra" "$DOCKER_LOG"

reset_env
run_svc down "web app"
expect_code 1 "down spaced name"
no_file "spaced name" "$DOCKER_LOG"

reset_env
run_svc down unknown
expect_code 1 "down unknown"
diag_has "unknown service" "unknown service unknown"
no_file "unknown does not call docker" "$DOCKER_LOG"

reset_env
G_TABLE="service|web|proj|relative|web|"
run_svc down web
expect_code 1 "relative workdir"
no_file "relative workdir" "$DOCKER_LOG"

reset_env
G_TABLE="service|web|proj|$TMPD/missing|web|"
run_svc down web
expect_code 1 "missing workdir"
diag_has "missing workdir" "workdir missing"
no_file "missing workdir" "$DOCKER_LOG"

reset_env
mkdir -p "$TMPD/work"
G_TABLE=$(printf '%s\n%s' "service|web|proj|$TMPD/work|web|" "service|web|other|$TMPD/work|web|")
run_svc down web
expect_code 1 "duplicate service"
no_file "duplicate" "$DOCKER_LOG"

# --- down / start ---

reset_env
mkdir -p "$TMPD/work"
G_TABLE="service|web|proj|$TMPD/work|webapp|"
run_svc down web
expect_code 0 "down ok"
expect_stdout "down stdout empty" ""
expect_file "down argv" "compose --project-directory $TMPD/work --project-name proj down -- webapp
" "$DOCKER_LOG"

reset_env
mkdir -p "$TMPD/work"
printf '%s\n' "services: {}" >"$TMPD/work/compose.yaml"
G_TABLE="service|web|proj|$TMPD/work|webapp|$TMPD/work/compose.yaml"
run_svc start web
expect_code 0 "start ok"
expect_file "start argv" "compose --project-directory $TMPD/work --project-name proj -f $TMPD/work/compose.yaml up -d -- webapp
" "$DOCKER_LOG"

reset_env
mkdir -p "$TMPD/work"
G_TABLE="service|web|proj|$TMPD/work|webapp|"
export DOCKER_RC=1
export DOCKER_STDERR="compose exploded"
run_svc down web
expect_code 1 "down compose fail"
diag_has "compose stderr" "compose exploded"
expect_stdout "down fail stdout" ""

reset_env
run_svc start missing
expect_code 1 "start unknown"
no_file "start unknown" "$DOCKER_LOG"

# --- update / update-status ---

reset_env
export SYSTEMCTL_ACTIVE=active
printf '%s\n' 'done' >"$G_STATUS"
run_svc update
expect_code 0 "update already running"
expect_file "status unchanged" "done
" "$G_STATUS"
no_file "no new unit" "$SYSTEMD_RUN_LOG"

reset_env
run_svc update extra
expect_code 1 "update extra"
no_file "update extra unit" "$SYSTEMD_RUN_LOG"
no_file "update extra status" "$G_STATUS"

reset_env
run_svc update
expect_code 0 "update starts"
expect_file "status stays running" "running
" "$G_STATUS"
expect_file "saw running before return" "running
" "$SYSTEMD_RUN_LOG.seen"
no_file "dnf not foreground" "$DNF_LOG"
if grep -F -q -- "--unit=gostodian-update" "$SYSTEMD_RUN_LOG" &&
	grep -F -q -- "--collect" "$SYSTEMD_RUN_LOG" &&
	grep -F -q -- "--property=Type=exec" "$SYSTEMD_RUN_LOG" &&
	grep -F -q -- "SERVICE_RESULT" "$SYSTEMD_RUN_LOG" &&
	grep -F -q -- "echo done > $G_STATUS" "$SYSTEMD_RUN_LOG" &&
	grep -F -q -- "echo failed > $G_STATUS" "$SYSTEMD_RUN_LOG" &&
	grep -F -q -- "dnf -y update" "$SYSTEMD_RUN_LOG" &&
	! grep -F -q -- "--wait" "$SYSTEMD_RUN_LOG"; then
	ok
else
	bad "update argv"
	cat "$SYSTEMD_RUN_LOG" >&2
fi

reset_env
export SYSTEMD_RUN_RC=1
run_svc update
expect_code 1 "systemd-run fail"
expect_file "status failed" "failed
" "$G_STATUS"
expect_file "was running at launch" "running
" "$SYSTEMD_RUN_LOG.seen"
diag_has "systemd-run" "systemd-run failed"

reset_env
saved=$PATH
PATH="/usr/bin:/bin"
export PATH
run_svc update
PATH="$saved"
export PATH
expect_code 1 "dnf missing"
expect_file "dnf missing writes failed" "failed
" "$G_STATUS"
no_file "no unit without dnf" "$SYSTEMD_RUN_LOG"

reset_env
run_svc update-status
expect_code 0 "status missing code"
expect_stdout "status missing" "failed
"

reset_env
: >"$G_STATUS"
run_svc update-status
expect_code 0 "status empty code"
expect_stdout "status empty" "failed
"

reset_env
printf '%s\n' running >"$G_STATUS"
run_svc update-status
expect_code 0 "status running code"
expect_stdout "status running" "running
"

reset_env
printf '%s\n' "DONE leftover words" >"$G_STATUS"
run_svc update-status
expect_code 0 "status done code"
expect_stdout "status done" "done
"

reset_env
printf '%s\n' weird >"$G_STATUS"
run_svc update-status
expect_code 0 "status other code"
expect_stdout "status other" "failed
"

reset_env
printf '%s\n' running >"$G_STATUS"
run_svc update-status extra
expect_code 1 "status extra"

# --- reboot ---

reset_env
run_svc reboot extra
expect_code 1 "reboot extra"
no_file "reboot extra" "$SYSTEMCTL_LOG"

reset_env
run_svc reboot
expect_code 0 "reboot"
expect_file "reboot argv" "reboot
" "$SYSTEMCTL_LOG"

reset_env
export SYSTEMCTL_RC=3
run_svc reboot
expect_code 3 "reboot fail"

# --- collect-logs ---

reset_env
logdir=$TMPD/logs
mkdir -p "$logdir"
printf '%s\n' old >"$logdir/dnf.log-20200101"
printf '%s\n' new >"$logdir/dnf.log-20200102"
printf '%s\n' cur >"$logdir/dnf.log"
printf '%s\n' secret >"$logdir/secure"
G_TABLE="log|dnf|$logdir/dnf.log|"
run_svc collect-logs dnf
expect_code 0 "collect dnf"
{
	printf '# %s\n' "$logdir/dnf.log-20200101"
	printf '%s\n' old
	printf '# %s\n' "$logdir/dnf.log-20200102"
	printf '%s\n' new
	printf '# %s\n' "$logdir/dnf.log"
	printf '%s\n' cur
} >"$TMPD/want-collect"
expect_stdout_file "collect order" "$TMPD/want-collect"
if [ -f "$logdir/dnf.log" ] && [ -f "$logdir/secure" ]; then
	ok
else
	bad "collect deleted logs"
fi

reset_env
logdir=$TMPD/logs
mkdir -p "$logdir"
printf 'plain' >"$logdir/boot.log-20240101"
G_TABLE="log|boot|$logdir/boot.log|"
run_svc collect-logs boot
expect_code 0 "rotation only"
{
	printf '# %s\n' "$logdir/boot.log-20240101"
	printf '%s' plain
} >"$TMPD/want-rot"
expect_stdout_file "rotation bytes" "$TMPD/want-rot"

reset_env
G_TABLE="log|secure|$TMPD/no-such-dir/secure|"
run_svc collect-logs secure
expect_code 1 "collect none"
diag_has "no files" "no files for secure"

reset_env
logdir=$TMPD/logs
mkdir -p "$logdir"
printf '%s\n' x >"$logdir/fail2ban.log"
printf '%s\n' y >"$logdir/fail2ban.log-20200101"
chmod 000 "$logdir/fail2ban.log-20200101"
G_TABLE="log|fail2ban|$logdir/fail2ban.log|"
run_svc collect-logs fail2ban
expect_code 1 "unreadable rotation"
diag_has "unreadable" "not readable"
chmod 644 "$logdir/fail2ban.log-20200101" 2>/dev/null || true

reset_env
run_svc collect-logs
expect_code 1 "collect no kind"

reset_env
run_svc collect-logs DNF
expect_code 1 "collect bad kind"

reset_env
run_svc collect-logs dnf extra
expect_code 1 "collect extra"

reset_env
logdir=$TMPD/logs
mkdir -p "$logdir"
printf '%s\n' onlydnf >"$logdir/dnf.log"
G_TABLE=$(printf '%s\n%s' "log|dnf|$logdir/dnf.log|" "log|boot|$logdir/boot.log|")
run_svc collect-logs boot
expect_code 1 "other kind ignored"

# --- resources ---

reset_env
run_svc resources
expect_code 0 "resources"
expect_stdout "resources body" "RAM
MemTotal: 1000 kB
MemAvailable: 400 kB
CPU
loadavg: 0.01 0.02 0.03
nproc: 2
Storage
/dev/sda1 20G 10G 9.0G 53% /
"

reset_env
printf '%s\n' "MemTotal: 1000 kB" >"$G_MEM"
run_svc resources
expect_code 1 "resources missing available"
diag_has "mem available" "MemAvailable missing"

reset_env
export DF_RC=1
run_svc resources
expect_code 1 "resources df"
diag_has "df" "df failed"

reset_env
run_svc resources extra
expect_code 1 "resources extra"

# --- health ---

reset_env
export SS_RC=99
export DOCKER_RC=99
run_svc health
expect_code 0 "empty health"
expect_stdout "empty health stdout" ""
no_file "empty health docker" "$DOCKER_LOG"

reset_env
printf '%s\n' "web true" >"$DOCKER_STATE"
printf '%s\n' "State Recv-Q Send-Q Local Address:Port Peer Address:Port" "LISTEN 0 128 127.0.0.1:8080 0.0.0.0:*" "LISTEN 0 128 [::]:22 [::]:*" >"$SS_FILE"
G_TABLE=$(printf '%s\n%s\n%s' "container|web" "port|8080" "port|22")
run_svc health
expect_code 0 "health ok"
expect_stdout "health lines" "container web
port 8080
port 22
"
no_file "health success log" "$G_DIAG"

reset_env
printf '%s\n' "web false" "api true" >"$DOCKER_STATE"
printf '%s\n' "LISTEN 0 128 0.0.0.0:18080 0.0.0.0:*" >"$SS_FILE"
G_TABLE=$(printf '%s\n%s\n%s' "container|web" "container|api" "port|8080")
run_svc health
expect_code 1 "health fail"
expect_stdout "health fail stdout" ""
diag_has "container down" "container web not running"
diag_has "port closed" "port 8080 not listening"
if grep -F -q "container api not running" "$G_DIAG"; then
	bad "healthy container logged"
else
	ok
fi

reset_env
run_svc health extra
expect_code 1 "health extra"

# 표에 서비스 이름을 넣어 두지 않는다.
if grep -E '^service\|' "$ROOT/gostodian-svc" >/dev/null || grep -E '^container\|' "$ROOT/gostodian-svc" >/dev/null || grep -E '^port\|' "$ROOT/gostodian-svc" >/dev/null; then
	bad "committed table has service names"
else
	ok
fi

# 이 머신의 /proc 로 resources 형식을 한 번 본다. 목은 PATH에서 뺀다.
live=$(mktemp)
if env PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" "$ROOT/gostodian-svc" resources >"$live" 2>"$TMPD/live.err"; then
	if head -n 1 "$live" | grep -qx RAM &&
		grep -qx CPU "$live" &&
		grep -qx Storage "$live" &&
		grep -q '^MemTotal: [0-9][0-9]* kB$' "$live" &&
		grep -q '^MemAvailable: [0-9][0-9]* kB$' "$live" &&
		grep -q '^loadavg: [^ ][^ ]* [^ ][^ ]* [^ ][^ ]*$' "$live" &&
		grep -q '^nproc: [1-9][0-9]*$' "$live"; then
		ok
	else
		bad "live resources shape"
		cat "$live" >&2
	fi
else
	bad "live resources exit"
	cat "$TMPD/live.err" >&2 || true
fi
rm -f "$live"

printf 'pass %s fail %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
