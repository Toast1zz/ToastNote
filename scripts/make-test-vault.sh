#!/usr/bin/env bash
# Generate a deterministic test vault: make-test-vault.sh <dir> [count=1000]
set -euo pipefail

dir="${1:?usage: make-test-vault.sh <dir> [count]}"
count="${2:-1000}"

mkdir -p "$dir"

awk -v dir="$dir" -v count="$count" 'BEGIN {
  srand(42)
  nf = 20
  ntags = split("工作 工作/周报 工作/会议 学习 学习/读书 想法 生活 旅行 菜谱 健身 代码 swift macos ai 设计 产品 日记 待办 项目 灵感 reading notes ideas todo meeting review draft archive inbox life tech", tags, " ")
  nzh = split("今天整理了一下最近的工作进度，发现还有不少事情需要跟进。 这个想法值得继续深入思考，也许可以做成一个小工具。 周末去了公园散步，天气很好，心情也不错。 读完了这一章，印象最深的是作者对习惯养成的描述。 会议里讨论了下个季度的目标和资源分配问题。 需要记得把文档同步给团队，并且确认每个人都收到了。 代码重构之后性能提升明显，但还要补充更多测试。 晚上做了一道新菜，味道比预期的要好很多。", zh, " ")
  nen = split("This is a short note about the project status. We should review the design again next week. Remember to follow up with the team on open items. The build is green and the benchmarks look stable. Draft the proposal and share it for feedback.", en, ".")
  if (en[nen] == "") nen--
  for (i = 1; i <= count; i++) {
    f = sprintf("%s/文件夹%02d", dir, (i % nf) + 1)
    system("mkdir -p \"" f "\"")
    path = sprintf("%s/笔记 %04d.md", f, i)
    target = 300 + int(rand() * 2700)
    out = sprintf("# 笔记 %d\n\n", i)
    len = length(out)
    while (len < target) {
      r = rand()
      if (r < 0.15) {
        blk = sprintf("## 小节 %d\n\n", int(rand() * 100))
      } else if (r < 0.35) {
        blk = ""
        for (k = 0; k < 3; k++) blk = blk "- " zh[1 + int(rand() * nzh)] "\n"
        blk = blk "\n"
      } else if (r < 0.45) {
        blk = "```swift\nlet value = " int(rand() * 1000) "\nprint(value)\n```\n\n"
      } else if (r < 0.65) {
        s = en[1 + int(rand() * nen)]
        sub(/^ +/, "", s)
        blk = s ".\n\n"
      } else {
        blk = zh[1 + int(rand() * nzh)] zh[1 + int(rand() * nzh)] "\n\n"
      }
      if (rand() < 0.2) blk = blk "#" tags[1 + int(rand() * ntags)] "\n\n"
      out = out blk
      len = length(out)
    }
    printf "%s", out > path
    close(path)
  }
}'
