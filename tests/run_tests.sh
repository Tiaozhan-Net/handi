#!/usr/bin/env bash
#
# 猜数小游戏 —— 自动测评脚本
#
# 题目要求:
#   程序随机生成一个 0~100 之间的数(用 math/rand 的 rand.Intn(x));
#   用户每次输入一个数字, 程序输出"猜大了"或"猜小了";
#   猜中时输出"胜利", 并在下一行输出"使用N次猜中"(N = 输入次数)。
#
# ---------------------------------------------------------------------------
# 测评思路(为什么这样测)
# ---------------------------------------------------------------------------
# 目标数是程序运行时随机生成的(Go 1.20 起每次运行都会重新随机), 因此:
#   * 不能写死一两次输入就指望猜中 —— 猜不中时程序会一直读输入;
#   * 也不能从程序输出里读出目标数 —— 只有"猜大了/猜小了"两条线索。
#
# 本脚本用的是"单调输入序列", 它有一个很好的性质: 无论目标数 t 是多少(0~100),
# 输出序列都是可以完全预测的, 于是每一条输出都能被精确比对。
#
#   升序序列 0,1,2,...,100:
#       t 之前每次输入都小于目标数 -> 恰好 t 行"猜小了", 然后"胜利";
#   降序序列 100,99,98,...,0:
#       t 之前每次输入都大于目标数 -> 恰好 (100-t) 行"猜大了", 然后"胜利"。
#
# 于是可以逐行断言:
#   * 猜中之前的每一行必须恰好是"猜小了"(升序)或"猜大了"(降序), 一行不多一行不少;
#   * 同一行如果出现另一种提示, 说明提示方向写反了, 立刻判错;
#   * 第 N+1 行必须是"胜利", 且 N(提示条数)必须落在 0~100 内;
#   * 再下一行必须是"使用N次猜中", 且 N 必须等于实际输入次数(计数不能 off-by-one);
#   * 之后不允许再有任何输出;
#   * 程序必须自己结束(退出码 0), 不能卡死。
#   升序 + 降序两局合起来, 把"猜大了""猜小了"两个分支都覆盖到。
#
# 另外单独测一局越界输入: 先输入 -1(目标数必在 0~100, 所以必然回答"猜小了"),
# 用它与随机结果无关地固定复现比较逻辑。
#
# 注意: 题目源码里 fmt.Scanln 没有检查错误, 一旦输入用尽就会拿旧的 guess 一直输出提示,
# 所以运行程序时必须加"行数上限 + 总耗时上限", 否则一份有 bug 的程序会把脚本拖死。
#
# ---------------------------------------------------------------------------
# 用法
# ---------------------------------------------------------------------------
#   bash tests/run_tests.sh                # 在任意目录执行都可以
#   bash tests/run_tests.sh --games 3      # 多玩几轮(默认 2 轮, 每轮目标数不同)
#   bash tests/run_tests.sh --no-color     # 关闭彩色输出
#   bash tests/run_tests.sh --keep-tmp     # 保留临时目录, 便于排查
#   SKIP_EDGE=1 bash tests/run_tests.sh    # 跳过"越界输入"用例
#
# 退出码: 全部用例通过 = 0, 任一用例失败 = 1
#
set -uo pipefail

# 本脚本用到数组、{fd} 形式的文件描述符和 BASH_SOURCE, 必须由 bash 执行
# (有些环境 sh 指向 dash, 用 sh 跑会报出难以理解的语法错误, 这里给个明确提示)
if [ -z "${BASH_VERSION:-}" ]; then
  echo "请用 bash 执行本脚本, 例如: bash tests/run_tests.sh" >&2
  exit 1
fi
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  echo "需要 bash 4.0 及以上版本(当前 ${BASH_VERSION})" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_GREEN=''; C_RED=''; C_YELLOW=''; C_BOLD=''; C_OFF=''
fi

PASSED=0
FAILED=0
ROUNDS="${ROUNDS:-2}"
BUILD_TIMEOUT="${BUILD_TIMEOUT:-180}"
PROGRAM_TIMEOUT="${PROGRAM_TIMEOUT:-30}"
KEEP_TMP=0

usage() {
  cat <<'EOF'
用法: bash tests/run_tests.sh [选项]

选项:
  --games N        测几轮(默认 2, 每轮目标数随机不同; 每轮含升序/降序两局)
  --no-color       关闭彩色输出
  --keep-tmp       保留临时目录(排查用)
  -h, --help       显示帮助

环境变量:
  SKIP_EDGE=1      跳过"越界输入(-1)"用例
  GAMES            同 --games
  BUILD_TIMEOUT    编译超时秒数, 默认 180
  PROGRAM_TIMEOUT  单局程序运行超时秒数, 默认 30
  NO_COLOR         非空时关闭彩色输出
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --games) ROUNDS="${2:-2}"; shift 2 ;;
    --games=*) ROUNDS="${1#*=}"; shift ;;
    --no-color) C_GREEN=''; C_RED=''; C_YELLOW=''; C_BOLD=''; C_OFF=''; shift ;;
    --keep-tmp) KEEP_TMP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$ROUNDS" in ''|*[!0-9]*) ROUNDS=2 ;; esac

# ---------------------------------------------------------------- 输出与断言
test_begin() { printf '\n%s>>> %s%s\n' "$C_BOLD" "$1" "$C_OFF"; }
ok()   { PASSED=$((PASSED + 1)); printf '  %s[PASS]%s %s\n' "$C_GREEN" "$C_OFF" "$1"; }
bad()  { FAILED=$((FAILED + 1)); printf '  %s[FAIL]%s %s\n' "$C_RED" "$C_OFF" "$1"; }
info() { printf '  %s[info]%s %s\n' "$C_YELLOW" "$C_OFF" "$1"; }

assert_eq() { # 实际值 期望值 说明
  if [ "$1" = "$2" ]; then ok "$3 (=$2)"; else bad "$3: 期望 [$2], 实际 [$1]"; fi
}

# ---------------------------------------------------------------- 环境准备
if ! command -v go >/dev/null 2>&1; then
  printf '%s未找到 go 命令, 请先安装 Go 并加入 PATH%s\n' "$C_RED" "$C_OFF" >&2
  exit 1
fi
cd "$PROJECT_ROOT" 2>/dev/null || { echo "无法进入项目目录: $PROJECT_ROOT" >&2; exit 1; }

MODROOT="$(go env GOMOD 2>/dev/null || true)"
if [ -z "$MODROOT" ] || [ "$MODROOT" = "/dev/null" ]; then
  printf '%s在 %s 未找到 go.mod(Go 模块根目录)%s\n' "$C_RED" "$PROJECT_ROOT" "$C_OFF" >&2
  exit 1
fi
MODROOT="$(cd "$(dirname "$MODROOT")" && pwd)"

TMP_DIR="$(mktemp -d 2>/dev/null || true)"
if [ -z "$TMP_DIR" ]; then
  TMP_DIR="$SCRIPT_DIR/.tmp.$$"
  mkdir -p "$TMP_DIR" || { echo "无法创建临时目录" >&2; exit 1; }
fi
PIDS=()
cleanup() {
  local p
  for p in ${PIDS[@]+"${PIDS[@]}"}; do
    kill -9 "$p" 2>/dev/null || true
    wait "$p" 2>/dev/null || true
  done
  if [ "$KEEP_TMP" -eq 1 ]; then
    printf '\n临时目录已保留: %s\n' "$TMP_DIR"
  else
    rm -rf -- "$TMP_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s===== 猜数小游戏 自动测评 =====%s\n' "$C_BOLD" "$C_OFF"
echo "Go 版本    : $(go version 2>/dev/null)"
echo "模块根目录 : $MODROOT"
echo "测试轮数   : $ROUNDS"

# ---------------------------------------------------------------- 静态检查
is_game_source() {
  [ -f "$1" ] || return 1
  LC_ALL=C grep -q 'rand\.Intn' "$1" 2>/dev/null || return 1
  LC_ALL=C grep -q 'package main' "$1" 2>/dev/null || return 1
  return 0
}

static_check() {
  local f found=''
  test_begin "1. 源码静态检查 (math/rand 与 0~100 取值)"
  for f in "$MODROOT"/*.go; do
    [ -f "$f" ] || continue
    case "$f" in *_test.go) continue ;; esac
    if is_game_source "$f"; then found="$f"; break; fi
  done
  if [ -z "$found" ]; then
    bad "未找到使用 rand.Intn 的 main 包源码文件"
    return
  fi
  info "被测源码: $(basename "$found")"
  if LC_ALL=C grep -q '"math/rand"' "$found"; then
    ok '已导入 "math/rand" 包'
  else
    bad '未导入 "math/rand" 包'
  fi
  if LC_ALL=C grep -q 'rand\.Intn(101)' "$found"; then
    ok '使用 rand.Intn(101), 随机数范围正是 0~100'
  else
    bad '未找到 rand.Intn(101)(题目要求生成 0~100 之间的数)'
  fi
}

# ---------------------------------------------------------------- 对局校验
# $1 = 用例标题
# $2 = 输入序列文件
# $3 = 猜中之前应当出现的提示("猜小了" 或 "猜大了")
# $4 = 可选: 在序列最前面额外插入的越界输入(例如 -1), 该行也必须给出 $3 这个提示
check_sequence() {
  local label="$1" seqfile="$2" expect_hint="$3" probe="${4:-}"
  local in_file out_file rc lines limit
  local hints=0 out=0 line

  test_begin "$label"

  in_file="$TMP_DIR/in.$$.$RANDOM"
  out_file="$TMP_DIR/out.$$.$RANDOM"
  if [ -n "$probe" ]; then
    { printf '%s\n' "$probe"; cat "$seqfile"; } >"$in_file"
  else
    cp "$seqfile" "$in_file"
  fi

  # 正确程序最多输出 102 行; 给足余量的同时必须设上限, 防止有 bug 的程序无限输出把磁盘写满
  limit=500
  # 题目源码的 fmt.Scanln 不检查错误: 输入用尽后会拿旧值疯狂输出提示, 因此必须限时限量
  if command -v timeout >/dev/null 2>&1; then
    timeout "$PROGRAM_TIMEOUT" "$MAIN_BIN" <"$in_file" 2>"$TMP_DIR/err.log" | head -n "$limit" >"$out_file"
  else
    "$MAIN_BIN" <"$in_file" 2>"$TMP_DIR/err.log" | head -n "$limit" >"$out_file"
  fi
  rc=$?

  # 题目源码最后一行 fmt.Printf("使用%d次猜中", cnt) 没有换行符。
  # 缺换行时 read 会把最后一行交出来但返回非 0(EOF), 循环会漏读这一行, 所以先补一个换行。
  if [ -s "$out_file" ]; then
    [ "$(tail -c 1 "$out_file" | wc -l | tr -d ' ')" = "1" ] || printf '\n' >>"$out_file"
  fi
  lines="$(wc -l <"$out_file" 2>/dev/null | tr -d ' ')"

  if [ "$rc" -eq 124 ]; then
    bad "程序在 ${PROGRAM_TIMEOUT}s 内没有结束(未能猜中, 或输出失控后被强制终止)"
    rm -f "$in_file" "$out_file"
    return
  fi
  if [ "${lines:-0}" -ge "$limit" ]; then
    bad "程序输出达到上限 ${limit} 行仍未结束(说明它没能猜中, 输入用尽后仍在输出)"
    rm -f "$in_file" "$out_file"
    return
  fi

  # 逐行核对:
  #   猜中之前 -> 每行都必须是 $expect_hint
  #   猜中那一行 -> 必须是"胜利"
  #   下一行 -> 必须是"使用N次猜中", N = 实际输入次数
  #   再往后 -> 不允许有任何输出
  local win_at=0 count_line='' extra=0
  exec {FD_SEQ}<"$out_file"
  while IFS= read -r line <&"$FD_SEQ"; do
    out=$((out + 1))
    if [ "$win_at" -eq 0 ]; then
      if [ "$line" = "$expect_hint" ]; then
        hints=$((hints + 1))
      elif [ "$line" = "胜利" ]; then
        win_at=$out
      elif [ "$line" = "猜大了" ] || [ "$line" = "猜小了" ]; then
        bad "第 ${out} 行输出 [$line], 但猜中之前应输出 [${expect_hint}](提示方向写反或比较逻辑有误?)"
        exec {FD_SEQ}<&-
        rm -f "$in_file" "$out_file"
        return
      else
        bad "第 ${out} 行输出非预期内容 [$line](只允许 猜大了/猜小了/胜利)"
        exec {FD_SEQ}<&-
        rm -f "$in_file" "$out_file"
        return
      fi
    else
      if [ "$out" -eq "$((win_at + 1))" ]; then
        count_line="$line"
      else
        extra=$((extra + 1))
      fi
    fi
  done
  exec {FD_SEQ}<&-

  if [ "$win_at" -eq 0 ]; then
    bad "输出里没有出现\"胜利\"(程序未能猜中)"
    rm -f "$in_file" "$out_file"
    return
  fi

  # 猜中前收到 hints 条提示, 说明第 hints+1 次输入才猜中
  if [ "$hints" -gt 100 ]; then
    bad "猜中前的提示有 ${hints} 条, 超出 0~100 的范围(最多 101 次输入就该猜中)"
  else
    ok "猜中前恰好 ${hints} 行\"${expect_hint}\", 第 $((hints + 1)) 次输入猜中"
  fi

  local expect="使用${win_at}次猜中"
  if [ -z "$count_line" ]; then
    bad "\"胜利\"之后没有输出\"使用N次猜中\""
  elif [ "$count_line" = "$expect" ]; then
    ok "\"胜利\"下一行输出 [$count_line], 次数与\"猜中是第几次输入\"一致"
  elif [ "$count_line" = "使用${hints}次猜中" ]; then
    bad "计数 off-by-one: 实际输入 ${win_at} 次才猜中, 程序却输出 [$count_line]"
  else
    bad "\"胜利\"下一行计数不正确: 期望 [$expect], 实际 [$count_line]"
  fi

  if [ "$extra" -eq 0 ]; then
    ok "计数行之后没有多余输出"
  else
    bad "计数行之后还有 ${extra} 行多余输出"
  fi

  info "本局共 ${win_at} 次输入, ${hints} 条提示, 输出 ${out} 行"
  rm -f "$in_file" "$out_file"
}

# ---------------------------------------------------------------- 主流程
test_begin "0. 编译"
MAIN_BIN="$TMP_DIR/main.bin"
if command -v timeout >/dev/null 2>&1; then
  ( cd "$MODROOT" && timeout "$BUILD_TIMEOUT" go build -o "$MAIN_BIN" . ) >"$TMP_DIR/build.log" 2>&1
else
  ( cd "$MODROOT" && go build -o "$MAIN_BIN" . ) >"$TMP_DIR/build.log" 2>&1
fi
if [ $? -eq 0 ] && [ -x "$MAIN_BIN" ]; then
  ok "go build 通过"
else
  bad "go build 失败:"
  sed 's/^/        /' "$TMP_DIR/build.log" >&2
  printf '\n%s结果: 通过 %d, 失败 %d%s\n' "$C_RED" "$PASSED" "$FAILED" "$C_OFF"
  exit 1
fi

static_check

# 生成两套单调输入序列
ASC="$TMP_DIR/asc.txt"
DESC="$TMP_DIR/desc.txt"
seq 0 100 >"$ASC"
seq 100 -1 0 >"$DESC"

r=1
while [ "$r" -le "$ROUNDS" ]; do
  check_sequence "2.$r.a 第 $r 轮: 升序输入 0→100 (应全为\"猜小了\")" "$ASC" "猜小了"
  check_sequence "2.$r.b 第 $r 轮: 降序输入 100→0 (应全为\"猜大了\")" "$DESC" "猜大了"
  r=$((r + 1))
done

if [ "${SKIP_EDGE:-0}" = "1" ]; then
  test_begin "3. 越界输入 (-1)"
  info "SKIP_EDGE=1, 已跳过"
else
  check_sequence "3. 越界输入 -1 (目标数必 >= 0, 必答\"猜小了\")" "$ASC" "猜小了" "-1"
fi

# ---------------------------------------------------------------- 汇总
printf '\n%s===== 测评结果 =====%s\n' "$C_BOLD" "$C_OFF"
if [ "$FAILED" -eq 0 ]; then
  printf '通过: %s%d%s    失败: %s0%s\n' "$C_GREEN" "$PASSED" "$C_OFF" "$C_GREEN" "$C_OFF"
  printf '%s全部用例通过%s\n' "$C_GREEN" "$C_OFF"
  exit 0
fi
printf '通过: %s%d%s    失败: %s%d%s\n' "$C_GREEN" "$PASSED" "$C_OFF" "$C_RED" "$FAILED" "$C_OFF"
printf '%s存在未通过用例%s\n' "$C_RED" "$C_OFF"
exit 1
