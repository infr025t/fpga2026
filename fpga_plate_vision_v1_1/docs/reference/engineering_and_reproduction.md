# 工程组织与复现

## 目录与模块边界

发布根目录由`project/`、`docs/`、`release/`和`evidence/`组成。源码与执行入口放入project，说明资料、已确认程序和验证证据各自独立；历史基线放在evidence/baseline。用户入口见[根readme](../../readme.md)。

| 路径 | 职责 |
|---|---|
| `project/rtl/top` | 模式选择、帧接纳和顶层连接 |
| `project/rtl/drivers/camera` | SCCB、上电控制、FIFO读取及同步资格判定 |
| `project/rtl/drivers/display` | LCD初始化、窗口命令和8080写事务 |
| `project/rtl/drivers/uart` | 字节级收发 |
| `project/rtl/video` | 行缓存、高斯、Sobel、显示接收、文字和ROI覆盖 |
| `project/rtl/recognition` | 小图所有权、定位、分割、归一化和CNN |
| `project/rtl/debug` | 测试图、快照、旁路观察和人工回放 |
| `project/rtl/common` | 通用整数运算 |
| `project/pc` / `project/pc_diag` | 主观察器、数学参考及诊断工具 |
| `project/model` | 发布所需冻结权重和量化元数据 |
| `project/sim` / `project/scripts` | 仿真、构建和结构检查入口 |
| `evidence/implementation` | 发布BIT对应的冻结源码、布线与时序报告 |
| `evidence/validation` | 当前及前版板测原始数据、PC回放和验证记录 |
| `evidence/baseline` / `evidence/history` | 保留输入夹具、历史板测和原始说明 |
| `evidence/release_checks` | 发布整理后的检查输出 |

40个RTL模块各自对应一个文件，`project/config/rtl_sources.txt`统一定义构建与仿真源集合。驱动层处理引脚、字节或像素；识别策略由recognition层承担。分割内部状态机保持完整工作单元，以统一RAM读时序和候选队列所有权。

v1.1的源码和白字验证在独立实验副本完成，原v1.0保持不变。白字构建使用 `project/build/white_characters_01`；正式目录沿用相同的四目录布局，文档链接均相对发布根目录。

## 发布身份验证

以下命令在发布根目录执行：

```powershell
python project/scripts/verify_release.py
python project/scripts/check_engineering.py
```

发布校验按release_manifest.json选择对应构建的冻结源，检查模块命名、清单覆盖、依赖方向、模型与下载文件哈希。v1.1冻结53项，其中49项RTL/模型/约束/配置文件逐字节核验；与v1.0的变更范围另由[两RTL变更审计](../../evidence/blue_polarity/source_change_audit.json)记录。新实现与板测证据见[当前验证](current_validation.md)。

## 构建

工具基准为Vivado2025.1，目标器件`xc7a35tcpg236-1`；Python依赖见[requirements.txt](../../project/requirements.txt)。进入project后选择新的输出目录：

```powershell
Set-Location project
powershell -ExecutionPolicy Bypass -File build.ps1 -OutDir build/rebuild_01
```

`build.ps1`调用构建Tcl；`freeze_sources.py`按中央清单复制RTL、模型、约束和脚本，记录SHA256，随后Vivado从冻结副本综合。流程生成VIO IP、综合顶层、检查锁存器、布局布线并导出时序、资源与DRC。重复使用已有冻结目录会被拒绝，以保留原构建身份。

如初次时序未收敛，可依既有`refine_timing.tcl`做物理优化并重新检查setup/hold；当前发布的初次和最终报告均保留。新的BIT应与其自己的冻结清单、LTX和实现报告共同使用。项目脚本需要本机Vivado和Python路径可用，工具发现/覆盖方式以各入口参数为准；新的输出写入project的生成目录，不覆盖release中的确认程序。

## 离线验证

在`project/`执行：

```powershell
python -m unittest discover -s pc -p 'test_*.py' -v
powershell -ExecutionPolicy Bypass -File scripts/run_engineering_controls.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_mode_transition.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_auto_split_scene_sim.ps1 -Tag verify_split_01
powershell -ExecutionPolicy Bypass -File scripts/run_auto_manual_sim.ps1 -Tag verify_manual_01
powershell -ExecutionPolicy Bypass -File sim/run_lcd_text.ps1
```

控制仿真比较startup和pattern的逐周期行为；模式仿真覆盖退出、重入、人工和诊断优先；自主整链采用实际工作模块；LCD测试重建总线写入像素。具体ROI边界与采集中止回归入口见[区域显示](roi_overlay_and_options.md)。已有日志表示对应版本执行结果，运行新的命令会生成独立新记录。

保存wire可脱离开发板回放：

```powershell
python pc/observe_auto.py --wire ../evidence/baseline/reports/split_aligned_repeat_100/wire.bin --frames 100 --truth BD12345 --out reports/replay_new_01
```

解析器保留旧协议语义，按其版本选择参考算法。原始图、分割、归一化及分数在同一frame_id下组装，分别验证数学一致性和真值文本。

## 板端使用与调试

独立运行不需要PC参与每帧计算。UART观察器接收后先落盘，结束采集再复算参考；诊断拥塞不会向识别核心施加反压。硬件下载和模式控制命令见[接口与操作](interfaces_and_operation.md)。当前发布已完成Flash写入、校验与QSPI重新加载验证，复现入口见[Flash与启动](flash_and_startup.md)。

VIO控制会覆盖实体开关；自动检查结束后使用physical动作交回实体开关。新测试记录应保留BIT身份、接线与模式、场景、完整结果和评价方法。失败输入与历史结果放在evidence中，不与下一次成功数据相互覆盖。
