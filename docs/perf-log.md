# ToastNote 性能记录

每个阶段结束时按 spec 第 3 节的方法实测并追加一行。

| 日期 | 阶段 | DMG 体积 | .app 体积 | 冷启动 | 空闲内存 | 空闲 CPU | 备注 |
|---|---|---|---|---|---|---|---|
| 2026-10-02 | M1 | — | 3.2 MB（Debug） | 未测（尚无 signpost） | RSS 约 125 MB（Debug，1000 篇库，未开标签；活动监视器“内存”口径会更低，Release 待测） | 0.0% | 冷启动 signpost 在 M2 加入；内存超预算需在 Release 构建下复测 |
| 2026-10-02 | M2（编辑器） | — | — | 210–320 ms（Debug，进程创建到窗口可交互，`os_log` 的 `cold launch to editor ready`；新构建首次启动 4.7 s 不计） | 未重测（M1 Debug RSS 约 125 MB，Release 待测） | 未重测 | 1 万字笔记，Release 构建（swift test -c release）：解析+样式中位数 3.3 ms（低于 4 ms 门槛，未启用局部重解析兜底）；整篇重刷 9.5 ms；单次按键（含增量属性更新与排版）中位数 7.2 ms，最大 36 ms（偶发）。 |
| 2026-10-02 | M5（索引） | — | — | — | — | — | 首次索引 1000 篇笔记：0.34 s（`swift test` Debug 构建，临时目录，含 swift-markdown 解析与标签提取），预算 5 s。空闲内存待 Task 35 统一实测。 |
| 2026-10-02 | M7（发布前核对） | 2.5 MB | 7.1 MB | 336 ms（Release，含恢复 5 个标签） | 73 MB（footprint，1000 篇库、5 个标签、静置 40 s） | 0.0%（60 s 内采样均为 0.0） | 全部预算达标。单次按键 1 万字中位数 7.2 ms（Release）；首次索引 1000 篇 0.34 s（Debug）。ad-hoc 签名的 Release 需关闭库验证才能加载 Sparkle（见 scripts/build-dmg.sh）。 |
| 2026-10-03 | 编辑器对齐修复后复测 | — | — | — | RSS 约 137 MB（Debug，1000 篇库，未开标签） | 0.0% | 光标、基线、行距、点击区域修复后，在 Agent Mac 虚拟机中测试（Xcode 27 beta），Release 构建（swift test -c release）：1 万字笔记单次按键中位数 5.54 ms，最大 15.4 ms；解析+样式 3.24 ms；整篇重刷 8.94 ms。 |
