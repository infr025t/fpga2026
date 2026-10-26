# 流式灰度视频保边降噪与细节增强

2026-10-26，第二阶段：已授权实现，模型验收已通过，正在补齐完整RTL核心。正式硬件仅维护VGA 640×480输入、632×472有效输出；最终主显示保留完整结果，缩小快照仅作诊断。

本目录是新版设计入口，基于 Basys 3 / XC7A35T。原工程 `../demo/stream_image_demo/` 保持原样。

**先读[设计规格1.6-full-vga-presentation](docs/spec.md)和[当前RTL计划](docs/plans/2026-10-23-rtl-core.md)。** 第15.A节第三轮finegain-v3受控模型**PASS**：51组调参候选中15组可行，按预登记质量余量规则选出ε1024/T_D2/T_E4/G428/L16，仅对此配置评估一次新保留集，17项必选全部通过，已发布[profile_id=1](model/profile.json)。模型审阅已通过并进入RTL实施；实际曝光与真实固定曝光视频仍按授权DEFERRED至相机集成。

[第三轮完整报告](reports/model_gate_round3/report.md)保存全部候选、失败前沿、独立输入、四模式图和来源哈希。代码`f1adeba`及独立登记`747c5da`均先于搜索；新文字/纹理和entropy2026102303噪声独立登记。保留主文字/纹理相对RAW为1.087972/1.125，ENHANCE阶跃越界2灰度、σ8空间/64帧时间噪声比1.018571/1.012451、新截断0.018939%。适用结论限已登记的受控主图，最差细线比0.978669，σ16文字未达到+5%；不保证任意输入都增强。10月24日最终37项测试PASS，614个旧归档/数值报告/demo/reference文件字节保持。精确除法器/token流水和[两轮窗口模块](reports/rtl/windows.md)的仿真及独立审阅均已通过；VGA窗口结果逐点核对，第二轮输出632×472。正在集成系数、重建与增强；完整数值核心、综合、布局布线和实板验证尚未完成。

[首轮模型质量报告](reports/model_gate/report.md)保存预登记输入/掩膜/哈希、全部候选、独立保留集四模式指标和图像。登记提交`cfe857b`先于参数搜索；首轮ε64/T_D2/T_E2/G_E384仅是预登记首项失败诊断，不是发布参数。数值参考VGA测试288组最大误差1 LSB；质量门槛失败不改变数值测试结果。

[第二轮独立保留集报告](reports/model_gate_round2/report.md)的登记提交`6b6ccc7`先于72项搜索；新主文字/斜纹图案及entropy2026102302噪声均独立登记。没有调参可行项，因此仅按预登记首项ε16/T_D2/T_E2/G_E384作一次保留集失败诊断，文字/RAW=0.929826、纹理/RAW=1.000000。已登记真实flat/text/texture区域及非空掩膜，公开照片与OV7670来源分开，未计算真实图clean PSNR。最终28项测试通过，原24组FAIL全部归档字节保持不变。

```powershell
python -m unittest discover -s stream_video_enhance/tests -v
# 已有正式结果直接查阅，不为探索参数重跑保留集。
# 在新空目录复现实验时，先登记并提交代码和输入，再运行：
python -m stream_video_enhance.model.evaluate --experiment finegain-v3 --register --report-dir <新目录>
python -m stream_video_enhance.model.evaluate --run --report-dir <新目录>
```

`evaluate --run`在受控质量PASS时返回0，FAIL/MISSING时返回1并保留报告；输入或登记无效时返回2。`unittest`命令独立检查测试是否通过，其退出码不代表受控质量结论。默认不指定目录的`--run`仍重放原始original-v1轮次。当前实验为`finegain-v3`：先提交执行代码，再在新空目录执行上面的`--experiment finegain-v3 --register --report-dir <新目录>`，提交生成的`registration.json`、`inputs.npz`与来源文件后，才执行该目录的`--run`。不得覆盖现有登记或根据保留集重选参数。

设计方向：固定 5×5 单尺度自引导滤波、两轮局部统计、软阈值细节增强；100 MHz 单核心时钟，帧内 II=1；两轮独立行缓存携带中心原像素，减少复杂的存储复用和对齐控制。每边裁掉 4 像素。诊断预览/串口读取独立的小快照，忙时跳过整帧预览，不能阻塞主处理链；最终主显示须完整呈现有效图像，另行验证接口与带宽。

本次修订撤销未经画质验证的增强默认值：先用同输入RAW/BASE/DENOISE/ENHANCE对照选定发布参数，再进入算法RTL。固定延迟由L_CORE统一推导，不要求凑成64拍。19,200 B快照增加同帧同坐标96×96 RAW/处理双ROI布局，采用16位成对写入，保持5个快照BRAM36；完整核心RAW/处理CRC通过图像包或独立STATUS可读取。新增诊断会增加少量逻辑与寄存器，未宣称资源成本为零。

预期效果是形成真正可连续工作的计算核心，并具备保边平滑和受控增强能力；真实曝光画质、资源、时序和摄像头帧率尚未验证。现有OV7670_FIFO的VGA并发适配仍需验证，旧QVGA路径不能只改尺寸后直接使用。最终主显示采用完整VGA逻辑画布；屏幕尚未购买，物理接口驱动尚未实现。推荐有显示存储的800×480完整模块，见[屏幕选型及带宽边界](docs/display_selection_2026-10-26.md)。

规格包含算法与定点规则、像素接口、逐级延迟、RAM端口、资源预算、错误恢复、外设边界及验收条件。模型数值与第三轮受控质量验收已通过；第一、二轮FAIL原样保留。公式、位宽与相对RAW的+5%门槛保持不变，后续变更仍按第17节处理。VGA在这里表示分辨率，屏幕接口仍独立待定。

- [本轮状态与交接](docs/status.md)
- [六项审阅意见的处理记录](docs/review_revision_2026-10-22.md)
- [原始交接说明快照](docs/reference/开发交接说明_2026-10-22.md)
- [用户提供的参考框图](docs/reference/system-reference.png)
