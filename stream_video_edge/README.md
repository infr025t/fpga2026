# V0.3稳定基线：RAW灰度／EDGE边缘

主工程已合入50张验收的相机修复：独立WRST控制、AL422读复位预取首字节计数、VSYNC短低脉冲资格判定。AEC自动曝光、AGC自动增益及AWB自动白平衡均保持开启。算法核心没有改变，当前读时钟2MHz、串口12Mbaud，仅访问COM10。

## 开始使用

1. 按[接线与使用](docs/wiring_and_use.md)连接，特别是 **WRST→JB1(A14)**；WRST与VSYNC断开，VSYNC→JC3保留。
2. 当前bit和匹配探针是`artifacts/edge_top.bit`、`edge_top.ltx`。所有实体SW先置0，执行`program.ps1`下载。
3. 单张手动采集：运行`receive_one.ps1`，LED0就绪后SW15从0拨到1。
4. 自动采集无需拨开关，窗口每张保存后更新：

```powershell
E:\Python\python.exe -B pc/receive.py --auto --source internal --frames 4
E:\Python\python.exe -B pc/receive.py --auto --source camera --frames 50
```

输出默认在`E:/FPGA_Test_Work/edge_v03_work/capture_时间戳`，不覆盖已有目录，不自动重试。依赖见`requirements.txt`；需安装时执行`E:\Python\python.exe -m pip install -r requirements.txt`。

## 画面与参数

VGA640×480输入；每帧选一次5×5自引导滤波或一次3×3高斯加权平滑，之后共用3×3Sobel，二者不串联。引导滤波内部的两轮窗口是必要算法步骤。输出为630×470有效区域，原坐标x5..634/y5..474；PC另存640×480黑边画布，不缩小或补造像素。

RAW是原始Y亮度灰度，不是彩色RGB。EDGE是Sobel阈值后的0/255图。默认引导滤波ε1024/T96，高斯平滑T128；支持手动阈值与离线扫描，尚无自适应阈值。不同模式先后采集，不是同一曝光的配对实验。强反光或遮挡时边缘可能变少，画质指标与FIFO拼接验收分别评估。

## 工程入口与目录

| 目录／文件 | 用途 |
|---|---|
| `rtl/core`、`model` | 核心计算及定点参考模型 |
| `rtl/camera` | SCCB初始化、独立WRST采集、VSYNC低脉冲判定 |
| `rtl/uart`、`pc/receive.py` | EVG2完整图像回传与接收校验 |
| `rtl/display` | 保留NT35510的8080驱动和显示像素接口 |
| `constraints` | Basys3相机／串口／WRST实际引脚 |
| `sim`、`tests`、`scripts` | 仿真、模型测试与构建工具 |
| `artifacts` | 当前主工程可下载bit和配套LTX |
| `reports/hardware/camera_acceptance_50` | 原50张验收、原始包和当时通过验收的bit |
| `reports/hardware/consolidated_*` | 整理后重新构建的实际回归结果 |
| `docs`、`reports/validation.md` | 当前规格、接线、接口、修改说明和验证结论 |

旧极性切换归零模块已移出活动工程；历史失败和旧硬件批次保留在测试归档，不作为当前使用说明。未生成ZIP。`demo`原工程未修改。

## 重新构建与验证

在本目录执行。Vivado2025.1安装于`E:/Vivado/2025.1`；`build.ps1`把工程和中间文件放到`E:/FPGA_Test_Work/edge_v03_work/stable_board`，成功后更新artifacts。

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1
E:\Python\python.exe -B -m unittest discover -s tests -v
E:\Python\python.exe -B scripts/run_camera_tests.py --tag mycheck
E:\Python\python.exe -B scripts/run_core_tests.py --size vga --tag mycheck
E:\Python\python.exe -B scripts/run_uart_tests.py --tag mycheck
E:\Python\python.exe -B scripts/generate_nt35510_rom.py --check
E:\Python\python.exe -B scripts/check_delivery.py
```

同名回归目录不覆盖；更换tag再运行。接屏前阅读[屏幕接口](docs/screen_interface.md)，当前bit未接通摄像头到LCD完整显示链路。下一步与工程清理记录见[修改说明](docs/changes_and_next.md)。
