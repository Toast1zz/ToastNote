# ToastNote 性能记录

每个阶段结束时按 spec 第 3 节的方法实测并追加一行。

| 日期 | 阶段 | DMG 体积 | .app 体积 | 冷启动 | 空闲内存 | 空闲 CPU | 备注 |
|---|---|---|---|---|---|---|---|
| 2026-10-02 | M1 | — | 3.2 MB（Debug） | 未测（尚无 signpost） | RSS 约 125 MB（Debug，1000 篇库，未开标签；活动监视器“内存”口径会更低，Release 待测） | 0.0% | 冷启动 signpost 在 M2 加入；内存超预算需在 Release 构建下复测 |
| 2026-10-02 | M2（编辑器） | — | — | 210–320 ms（Debug，进程创建到窗口可交互，`os_log` 的 `cold launch to editor ready`；新构建首次启动 4.7 s 不计） | 未重测（M1 Debug RSS 约 125 MB，Release 待测） | 未重测 | 1 万字笔记，Release 构建（swift test -c release）：解析+样式中位数 3.3 ms（低于 4 ms 门槛，未启用局部重解析兜底）；整篇重刷 9.5 ms；单次按键（含增量属性更新与排版）中位数 7.2 ms，最大 36 ms（偶发）。 |
| 2026-10-02 | M5（索引） | — | — | — | — | — | 首次索引 1000 篇笔记：0.34 s（`swift test` Debug 构建，临时目录，含 swift-markdown 解析与标签提取），预算 5 s。空闲内存待 Task 35 统一实测。 |
