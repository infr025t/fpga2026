# 异常台账与处理边界

本文件是工程参考材料，按证据保留失败、修复和限制。历史视频台账编号a01至a30沿用其原A01至A30含义；新增a31起为识别阶段事项。证据索引见[historical_evidence.md](historical_evidence.md)，实际读取文件及SHA256见[anomaly_sources.json](../../evidence/anomaly_sources.json)。历史原文件只读，文中“已通过”均绑定当时阶段，不等于本轮整理版已完成复测。

历史继承基线为`plate_autonomous_board_20261101/build_split`；v1.0绿色框基线为engineering_03，其新增事项见E06至E10；v1.1白字变更见E11。历史基线在完整入镜、当前BD12345场景取得100个连续完整识别组正确；源开始节拍22.50777 fps，OCR完成5.62696次/s。仍有B/H分类、复杂粘连、场景适用性及外部采集/显示机制的未闭合问题。这里不把历史固定场景验收改写为任意车牌识别准确率。[o01]、[o07]、[o08]

## 状态口径

- **观测成立**：原图、日志、计数或用户观察支持该现象；不自动确定原因。
- **原因确认**：有可定位的代码/配置错误及相应对照或复现；结论只覆盖该机制。
- **假设待证**：物理机制、相关性或候选解释，尚无独立测量闭环。
- **限定条件通过**：给定版本、样本及场景通过；不删除早期失败，不代表永久解决。
- **仍存在/未验收**：现象未修复或验证缺口仍在。计划与建议不算实施。

UART CRC表示上传包一致；队列两端CRC相同表示该路径两处一致；固定色条完整参考CRC可判定该图源内容是否正确。三者不能互相替代。160×120概览、中央条带和ROI只覆盖导出区域；原图参考一致也不等于识别文本正确。叠字后的屏幕最终像素不在原队列CRC中。[h01]、[o06]

## 历史视频链路事项

### a01 频闪暗纹；a02 斜向刷新分界

**a01**：改线后的实拍仍见均匀细纹、滚动或静止暗条，历史台账记载用户确认照明频闪并暂不处理。未做受控光源或照明波形实验，不能据此把浮雕、错块都归于频闪；本工程未实施该项修复。**a02**：强光或快速运动下出现斜向区域刷新，未独立定位。无TE同步、无双缓冲换页时的LCD扫描/写入交界，以及rolling shutter均为候选解释。尚无同次事件完整原帧和屏幕对照的专项验收；暂停前后对照只能辅助区分。[h01]，原A01/A02。

### a03 固定边缘阈值适应性；a04 失焦与细线

旧同图离线结果中Gaussian阈值128仅1个白点，改32为4066个，反映该图阈值敏感；不能据此统一改阈值。失焦调节后有所改善，但右边细线、分块不能全部归因失焦。旧引导滤波结果已退出当前Gaussian＋Sobel方案。当前实景边缘效果未由数字一致性自动验收；先排除相邻字节错取再评价阈值。[h01]，原A03/A04。

### a05 SCCB假ACK；a06 VSYNC/写窗口解释

早期开漏线无有效高电平、读回全零、遮挡后噪声不变；历史补电平网络后PID等关键寄存器及图像更新恢复。该特定样机网络不能作为通用接线规范，完成后的电气裕量没有完整测量。早期WR窗口/VSYNC高/低分别240/240/0行，不支持盲目翻转极性；内部计数正常不证明模块端收到正确WEN/WCK。QVGA的240行验收不能替代VGA480行。[h01]，原A05/A06。

### a07 FIFO容量；a08 WRST与VSYNC耦合

640×480×2=614400字节，超过AL422B的393216字节；仅灰度307200字节能放下不代表相机写入的YUV422完整帧能先冻结再慢读。当前连续读写、行信用策略受此约束，不能用放宽溢出门槛处理。早期重复细节块相隔196608灰度像素，支持旧轮次混入。WRST独立接JB1、目标帧读取不重复清零，旧单拍又调整尾部提交、预取和同步。旧2MHz、AEC/AGC开启的50张通过只成立于当时；后续高速故障复现保留。WRST耦合是设计风险，但没有模块端波形就不能唯一解释全部坏图。[h01]，原A07/A08。

### a09 固定右带；a10 读复位预取漏计；a11 Y字节固定选择

**a09**：历史水平窗口180/36改158/14后，两张实拍960行中的约18像素固定重复带消失；不是插值、裁边修图。其后40张仍有1张拼接，不能据固定右带消失宣称全图无错。**a10**：读复位已预取byte0而计数未纳入，属于确认的实现及模型覆盖缺陷；修正相位/总数后完整VGA模型和旧50张通过。**a11**：高速误取UV的CRC为`17e5bee9`，原尺度证据给出偶数Y参考`6df0b9b5`，采用`Y_BYTE=0`并计入byte0后通过对应模型。这些修正不能解释或消除运行中的Y/UV角色互换。[h01]、[h04]

### a12 VSYNC短脉冲；a13 HREF碎脉冲与错误现场

历史75行提前结束、同步后单拍短脉冲，以及短高脉冲漏滤均须保留。双向稳定资格判定修复模型中可复现的假边界；不同事件的电气来源未证明相同。强光/遮挡后停机时曾出现557行及1.55μs短HREF高，正常高约426.7μs。短低脉冲拆行造成虚增credit可由模型重现；`0x22`不能独自证明FIFO真实塞满。首错锁存保留错误上下文。首次把滤波HREF同时用于WEN/WRST预备边界的候选引入整灰/浮雕，已回退到只改计数/credit，不能遗漏失败候选。近光外部触发仍待测。[h01]，原A12/A13。

### a14 高速旧FIFO区间与后续内容错误

第85帧前147456像素、另轮第105帧前98304像素异常，可按旧FIFO轮次重建CRC；错误到物理回绕结束。FAST改SLOW后1500帧通过，但暂停恢复epoch1从index52395起错，EDGE375帧后也报错；旧脚本没保存坏CRC，末帧inspection不能冒充故障现场。2500帧专项为2499正确、1错，第866帧CRC`6823edd0`可重建为前86016像素旧轮次，第867恢复。这次0.04%仅为固定色条该轮统计。[h04]、[h07]、[h08]、[h09]

旧视频收敛候选在第324帧又报内容错误：两处CRC均`589fae6c`而正确值`6df0b9b5`，前61440像素错、首值45而期望206，行/字节/像素数完整。此事件由历史台账转述，本次未重开其fault.json；用户期间动过USB或供电，但对应时刻不清，不能唯一归因。连接恢复后各500帧色条、10轮暂停及实拍复测通过，也不能抹掉该失败。外部写入/读沿/刷新机制未闭合。[h01]，原A14。

### a15 白点、浮雕及相邻字节角色互换

8100帧计数和源/显示CRC自洽时仍可见错图；写屏前概览已经包含亮点/浮雕。30ns改40ns单次采样后，三张抽样≥250像素数由旧69/10/0变0/0/0，但场景曝光未严格固定，且第三张底部仍有浮雕。35ns延迟压力模型是人工模型，不是实测线缆延迟。600连续配对包CRC、缺号与FPGA丢包为0；第1/99帧通道角色相反，第25帧内互换，确认问题在写屏前且涉及字节角色。34帧疑似互换是特定黑白目标筛查，非通用错误率。未确认实际WCK、模块端多/少读沿或电气原因，未通过自动换字节、清bit7或复制像素掩盖问题。[h02]、[h03]、[h05]、[h10]

### a16 提频、信用与帧所有权

旧4/5/5.56MHz各6帧通过、6.25MHz末8行错，以及40MHz模型过而板测CRC错，均不构成当前线束频率上限。已确认需把phase0当前消费一字节纳入下周期credit审批，累计计数用32位模减，启动与暂停同拍不得撤销已接纳帧，裁边EDGE EOF不得替代源VGA排空。模型通过只覆盖建模行为，不证明外部模块收到相同边沿。[h01]、[h04]、[h05]

### a17 整组相机线缩短与反接风险；a18 独立读取边界

历史缩线实际改变的是**整组相机连线**，不是仅RCK的严格单变量实验；原接线约20cm，短转接线方案含供电/地回流和所有信号总路径。改线后RAW/EDGE各500帧色条及第二轮600有效实拍包有改善，但没有示波器/逻辑分析仪测得反射、串扰或模块端沿。不能写“已证明RCK过长为唯一根因”。历史3V3/GND接反后仍出图，也不能证明器件无潜在损伤。STM32独立GPIO重复读取与DMA结果是跨实现诊断，并未测出电气根因；STR后核定是STROBE而非WCK/PCLK，OE不等于独立RE。缺少WCK直接观测，行信用仍是推算值。[h01]、[h06]

### a19 LCD硬件位宽；a20 底部噪带

初始实物IM0=0、IM1=1与8位8080程序不匹配；按实物改IM0=IM1=0后独立点屏由用户确认。旧图纸跳阻位置与实物不同，不能照图误接。低速相机底部噪带、上下分界曾在同尺寸内部图正常时出现，后续写屏前又复现同类浮雕；未唯一归因，不能统称LCD故障或频闪。独立图、相机参考、写屏前数据及屏幕观察必须分别记录。[h01]，原A19/A20。

### a21 切模式吞帧/末字提前完成；a22 主动暂停

已确认的缺陷包括开关变化撞寄存start导致吞已接纳帧、零间隔新旧字同拍导致误判末字完成；历史修正锁存帧模式、清背景时撤ready和独立末字核算，并有定向仿真。它不解决TE/撕裂。VIO接管、快照导出或统计达标自动暂停与真正采集错误停机应区分；结束要交还实体开关并留控制状态，不能复位丢现场后宣称已定位。[h01]，原A21/A22。

### a23 USB/COM/JTAG断连；a24 UART坏包

COM10 PermissionError、ClearCommError、USB/JTAG枚举丢失及Xicom 50-38均有历史记录。改线首轮FPGA达600帧而主机仅保存316张后中断；第二轮600完整。调试核断连时帧计数仍可增长，不能直接认定视频核心死锁；重连后可能从QSPI启动原版时，固件身份不明的尝试不得算候选验收。历史台账记载用户移动USB/供电，但未建立逐事件因果链。配对色条初轮60有效包仍有1坏包/缺号；主机缓存扩至1MiB后600包正常，只说明该轮改善。诊断可丢包但不能反压核心，包损坏与采集内容错是不同层次。[h01]、[h03]、[h10]

### a25 Flash身份；a26 历史实现失败；a27 测试工具漏检；a28 版本漂移

Flash最初型号误选，后按JEDEC选择并完成旧视频固件校验/用户冷启动确认；该证据不属于OCR固件。RAM下载不具断电保持性，本轮文档工作未访问Flash。旧点屏除法、外部延迟重复预算与过大快照均曾导致实现失败，未通过不能视作可用BIT。工具还出现退出码0误判非法参数、零轮PASS、错误测试目标及BIT/LTX不配套等问题。早期源码采样相位、诊断大小和文档漂移要求每次绑定确切文件与哈希；旧板测、新仿真和另一版时序不能拼成“当前版全通过”。[h01]，原A25至A28。

### a29 已退出增强方案；a30 旧环境与能力误述

旧引导滤波默认参数没有相对RAW的放大区间，24/72组初轮门槛失败与后续受控模型通过均是历史方案，不能写成当前增强功能。路径缺失、pip SSL、错误端口及开漏输入警告属于工具/环境层；亮像素质心不等于目标检测，旧1Mbps单帧链不等于实时VGA。保留阶段范围，禁止将旧开关定义、协议或失败原因套到当前OCR工程。[h01]，原A29/A30。

### a31 AEC/AGC候选解释的限制

曝光/增益变化可能改变灰度、噪声和局部阈值输入，这是分析假设；本次资料没有关/开AEC、AGC且保持其余条件不变的成组原始对照，不能登记为某次错块、浮雕或停机的确认根因。旧50张验收恰在AEC/AGC开启条件通过；相邻字节在同帧互换的直接证据也不能由一般曝光变化解释。后续若检验，应保留寄存器状态、受控照明、同场景原字节对及帧边界，而非只比较照片亮暗。[h01]、[h03]、[h05]

## 识别阶段新增事项

### a32 固定ROI与背景连通；a33 移动/截边

旧ROI `(26,35,158,87)` 中数字与牌外背景连通，100帧虽数值参考全一致，却95次BD、5次B。改标定ROI `(26,41,150,76)` 后同场景新100帧完整BD12345。随后移动约9个小图像素导致固定ROI裁字；同帧平移ROI恢复，证明那次错误来自位置不适配，不是CNN数值失算。OSD阶段牌面下移后5次DM1O1AC、15次空结果，0/20正确也保留。[o04]、[o06]

动态定位仅面向完整入镜、近水平、亮底暗字且与背景有亮度区分的单牌。换成深底白字并右侧出画的10帧预检真值评分不适用；不能纳入准确率。build_split最初牌面底部出画的100组都是零字符：参考校验passed=true只证明空定位与参考一致，BD12345正确0/100。当前模型无法恢复画面外信息，完整入镜场景验收不消除此限制。[o02]、[o12]、[o13]

### a34 汉字碎片被识别为AG

完整入镜placement_test_03动态ROI `(7,67,156,107)` 定位成功，但左部汉字产生重叠碎片框，10张输出3次AGBD123K、7次AGBD123M。前缀版按候选中心排除ROI最左1/8，20帧AG消失而保留框不变，但仍13次BD123M、7次BD123K，整串0/20。此修复是版式几何排除，不是汉字识别；不应给无汉字或不同版式照搬开启。边界策略应由协议版本解释，不得用新算法覆盖旧ASG1/2记录。[o02]、[o03]、[o14]、[o15]

### a35 4/5细桥粘连及受限拆分

同帧二值图显示4、5主体有隙，下沿一行暗像素却使其成为约32×31的8连通域，交给CNN得到K/M。build_split在原域像素列投影中找稀疏切口，并以两子框高度/宽度/面积复核，失败退回原框；不硬编码BD12345或7字符。854张保存图中30张粘连图从0/30到30/30，其他824张框及预测不变，原1张B/H错误仍存在。[o01]、[o10]

最新连续100完整组从5249到5645，源帧号步长4，100/100 BD12345。旧规则88张会把4/5合并，新规则拆开；其余12张原已分开且7框保持。当前场景修复有直接同图对照。浓墨厚桥、三字连体、严重模糊和特殊宽字仍可能失败；有限M/W合成用例不能证明所有字体均不误拆。[o07]、[o08]、[o16]

### a36 B/H混淆与模型泛化

动态定位124张保存图中123次BD12345、1次HD12345；拆分854张回放仍保留该B/H错误。没有新增模型训练、多帧投票或按真值替换。[o02]、[o10] 冻结模型通用字体测试整数准确率为81.25%（2880个字符样本），与当前场景整牌100/100、浮点/整数一致率均为不同指标；不能写成任意字体或任意号码100%。训练字模与验证划分的独立性应在数据主题文档核验，本台账不以训练集高分作泛化证据。[m01]

### a37 遥测内部断片、会话边界及主动跳帧

split_aligned_100虽收齐100完整正确组，但5个不完整组包含会话开头1个及内部4个，CRC候选拒绝1，帧号额外间隔存在，不能称无丢失连续验收。bad_captures/publisher_dropped为0不足以唯一判断线上、USB或PC哪段丢失。复测split_aligned_repeat_100验收区间内源帧号步长均4，CRC候选拒绝0、板上采集错误/发布丢弃0；会话开始缺AIF1的1个残组和结束1200字节半包仍保留。[o01]、[o07]、[o09]

复测297个未识别源帧与忙时主动跳帧增量吻合，属于识别调度，不是视频丢帧；22.50777 fps源开始与5.62696次/s OCR必须分列，不能宣称22.5fps整牌识别或独立测得LCD光学刷新率。采集开始至结果平均161.77ms，不等于单字符CNN9.42444ms。[o08]

### a38 遥测负时序、优化后的裕量与资源

自主初版build_final WNS−0.474ns、58失败端点在遥测路径；历史报告记载增加选择与CRC/入队之间寄存级并优化后通过，不能跳过失败事实。build_split初次WNS−0.330ns、4失败端点；同RTL、100MHz/IO约束经物理优化后WNS+0.088ns、WHS+0.006ns，建立/保持失败端点0。最终15,587 LUT、18,829 FF、44.5 BRAM36等效、9 DSP属于build_split，不是本轮新整理版时序。BRAM占50块的89%，继续扩展须重新预算。[o01]、[o04]、[o11]、[t01]、[t02]、[t03]

### a39 叠字结果的时间语义与观察边界

屏幕显示最近完整识别结果，并在下个被接纳视频帧边界提交；不保证文字来自当前显示帧。同拍完成/帧起点延至再下一帧，暂停时文字不刷新。WAIT/NONE/ERR/OFF和超长`+`有明确语义；OSD仅显示前8字符不代表分割上限8。603300个LCD总线重建像素是仿真证据，不能当作屏幕照片；历史用户确认可见文字也不证明当前整机全部视觉缺陷已清除。[o06]

## 后续登记与结案要求

每次追加源码/冻结集合、BIT/LTX哈希、模式、接线、光照、对象与完整入镜状态、开始结束帧号、有效/不完整组、CRC拒绝、原始数据位置、准确率真值及是否适用。应分别填写观测事实、确认原因、待证解释、实施改动、回归范围和剩余缺口。对采集电气问题需要模块端实测或足够受控实验；对OCR需要独立号码/字体/位置数据，不能反复同场景替代；对新整理版需要它自身的仿真、实现和板测。失败不得被后一次通过覆盖。

[h01]: ../../evidence/history/release_lcd_v04/stream_video_edge_20fps/docs/anomaly_register.md
[h02]: ../../evidence/history/video20fps_20261030/docs/dynamic_image_fault_20261031.md
[h03]: ../../evidence/history/video20fps_20261030/docs/byte_phase_evidence_20261031.md
[h04]: ../../evidence/history/video20fps_20261030/docs/diagnostic_findings.md
[h05]: ../../evidence/history/video20fps_20261030/docs/sample40_experiment.md
[h06]: ../../evidence/history/video20fps_20261030/docs/short_adapter_wiring.md
[h07]: ../../evidence/history/video20fps_20261030/docs/statistics2500_result.md
[h08]: ../../evidence/history/video20fps_20261030/reports/lcd/runtime/stats2500_run01/summary.json
[h09]: ../../evidence/history/video20fps_20261030/reports/lcd/runtime/stats2500_run01/bad_frame_analysis.json
[h10]: ../../evidence/history/video20fps_20261030/reports/uart_pairs/pair_uart_scene_01/summary.json
[o01]: ../../evidence/history/plate_autonomous_board_20261101/docs/touching_character_split.md
[o02]: ../../evidence/history/plate_autonomous_board_20261101/docs/placement_tolerance_report.md
[o03]: ../../evidence/history/plate_autonomous_board_20261101/docs/chinese_prefix_filter.md
[o04]: ../../evidence/history/plate_autonomous_board_20261101/docs/autonomous_board_test_report.md
[o05]: ../../evidence/history/plate_autonomous_board_20261101/docs/board_test_report.md
[o06]: ../../evidence/history/plate_autonomous_board_20261101/docs/lcd_result_overlay.md
[o07]: ../../evidence/baseline/reports/split_aligned_repeat_100/summary.json
[o08]: ../../evidence/baseline/reports/split_aligned_repeat_100/metrics.json
[o09]: ../../evidence/baseline/reports/split_aligned_100/summary.json
[o10]: ../../evidence/baseline/reports/split_reference/summary.json
[o11]: ../../evidence/baseline/reports/split_artifacts.json
[o12]: ../../evidence/baseline/reports/split_board_100/summary.json
[o13]: ../../evidence/baseline/reports/locator_board_precheck/context.json
[o14]: ../../evidence/baseline/reports/placement_test_03/diagnosis.json
[o15]: ../../evidence/baseline/reports/prefix_board_20/summary.json
[o16]: ../../evidence/baseline/reports/split_aligned_repeat_100/split_box_check.json
[t01]: ../../evidence/history/plate_autonomous_board_20261101/build_split/timing.rpt
[t02]: ../../evidence/history/plate_autonomous_board_20261101/build_split/timing_refined.rpt
[t03]: ../../evidence/history/plate_autonomous_board_20261101/build_final/timing.rpt
[m01]: ../../project/model/training_result.json
[p01]: ../archive/engineering_spec.md
[p02]: ../archive/engineering_plan.md


## 本轮整理版追加（不改写上述39项历史记录）

### E05：K38817汉字与边框候选残留，尚未解决

- 版本：`build/engineering_02`；本轮用户确认号码K38817。
- 现象：100/100完整结果多两个前导字符，WGK38817为65、MGK38817为35；整串正确0/100。末尾六字符100/100正确仅用于定位问题，不替代整串验收。
- 证据：[本轮详细记录](current_validation.md)、[原始组及汇总](../../evidence/validation/engineering_board_100/summary.json)、[框与前缀界线](../../evidence/validation/engineering_board_100/segmentation_failure.png)。
- 已确认：板上全部614400归一化像素、28800分数与软件相同；首帧两个多余候选中心均在左1/8排除线右侧，规则按既定条件放行。排除规则是位置假设，不是汉字分类。
- 未确认：任意字体/倾斜/背景下都能用同一修改解决；没有全位置网格数据。用户反馈放置范围苛刻，保留为待测缺陷。
- 本轮处理：记录并保留失败输入，不调阈值、不改核心算法；不能标为收敛重构已解决。
- 后续验收：分别统计边框误检、汉字残留、真字符误删、定位失败与整串准确率，使用未调参牌号及位置保留集。

本轮构建/路径等工程问题E01–E04见[前版归档](../archive/engineering_02_validation.md)，失败日志保留。它们与相机线缆/读取故障不同，不应合并成同一根因。


## 发布版工程与显示追加

### E01–E04：工程迁移、仿真入口和IP综合

| 编号 | 现象 | 处理与验证 |
|---|---|---|
| E01 | 中文PowerShell脚本解析失败 | 无BOM UTF8被Windows PowerShell按其他编码解析；脚本统一UTF8 BOM，相应runner通过 |
| E02 | 顶层编译信号前向声明冲突 | 将识别实例移到信号声明后，连接保持，完整编译与仿真通过 |
| E03 | 旧固定ROI测试缺recognition_enable端口，夹具路径失效 | 端口补常量1，修正输入路径并核对54份夹具SHA；固定ROI链通过，16份生成向量数值保持 |
| E04 | engineering_01综合报lcd_vio not found | 恢复synth_ip步骤，engineering_02独立完成构建；失败日志保留 |

详细过程及原始日志入口见[engineering_02验证归档](../archive/engineering_02_validation.md)。

### E06：绿色ROI显示与采集中止撤框，已回归

新增显示前，测试在LCD写事务x48,y116期望绿色07e0，实际得到灰度94b2，[失败日志](../../evidence/logs/roi_red.log)确认缺少覆盖。加入独立ROI模块后，三帧910500像素检查通过，边界、帧中更新、非法坐标和模式切换见[显示回归](../../evidence/logs/roi_green.log)与[边界回归](../../evidence/logs/roi_bounds.log)。

采集中止最初未发出撤框事件，旧框可能保留；随后增加旁路失效通知，保持原采集/识别状态机不变。[失败用例](../../evidence/logs/roi_abort_red.log)及[修正回归](../../evidence/logs/roi_abort_green.log)同时保留。当前规则在下一显示帧边界撤框，暂停显示时屏幕内容仍冻结；这属于显示提交时序。

### E07：engineering_03初次时序与最终工具提示

初次WNS−0.069ns、TNS−0.091ns，关键路径位于人工串口CRC；物理优化后WNS+0.029ns、WHS+0.050ns、TNS/THS=0。RTL、模型及约束保持一致。[初次](../../evidence/implementation/timing.rpt)、[最终](../../evidence/implementation/timing_refined.rpt)、[优化日志](../../evidence/implementation/refine.log)。

最终[DRC](../../evidence/implementation/drc_refined.rpt)摘要42项Warning：DPIP-1 8、DPOP-1 5、DPOP-2 5、DPOR-1 17、PDCN-1569 3、PLBUFGOPT-1 1、RPBF-3 2、RTSTAT-10 1；这与engineering_02的41项、历史build_split的43项不同。DRC摘要无Error/Critical Warning不等于整个构建日志无Critical Warning。工具日志还保留synth_ip在project模式的兼容提示及RCLK路径分段提示。

[check_timing](../../evidence/implementation/check_timing_refined.rpt)no_clock=0、unconstrained_internal_endpoints=0，13个no_input_delay输入已有false path，8个相机数据输入为partial_input_delay。静态收敛建立在所列约束之上，未新增模块端波形实测。后续变更必须重新实现，不继承本次slack。

### E08：当前前缀结果与接收窗口记录

E05在绿色框版本继续可见：用户确认目标为K38817，10个完整组输出1K38817两次、GK38817八次，整串精确匹配0/10；后六字符匹配不替代整串评分。70字符、53760归一化像素、2520分数全部与整数参考一致。定位、分割、CNN保护源未变，候选从8变7的两次采集并非受控场景对照；不能登记为识别算法修复。

当前[summary](../../evidence/validation/roi_board_10/summary.json)保留1个首部不完整组、590个接入丢弃字节、CRC候选拒绝0、尾截断1184字节；bad_captures和publisher_dropped最大值均0。前版100组保留590个接入丢弃字节、1个首部不完整组、CRC候选拒绝0、尾截断240字节。这些是原始会话边界与解析统计，完整组逐项一致不覆盖全部USB字节。历史内部断片另见a37，不能混合解释。

### E09：Flash与实体控制状态

当前ROI BIT已下载配置RAM，用户确认绿框显示。随后执行physical解除VIO覆盖，[日志](../../evidence/logs/roi_physical_console.log)保留；该动作没有重新下载或写Flash。断电后仍可能加载旧Flash程序及旧开关定义。发布BIT身份为8d2d8ed5c144a5d1618daad8c18fdd1ae9c5a99fb4e24623f98238f58167efae，当前整理没有把旧Flash登记成新版本。

### E10：训练来源与从零重现

冻结整数权重和保存的板测输入可以复算。历史数据生成依赖Windows字体、旧通用NPZ和vendor字模；没有完整的当时字体binary哈希、固定上游vendor commit、完整训练依赖锁及独立真实车牌身份划分。训练/验证车牌字模同源、随机增强seed不同；通用字体测试整数准确率81.25%，车牌字模合成测试99.117647%。各集合单独保留，未将合成字符分数当作真实整牌性能。详见[模型资料](model_and_training.md)。


## v1.1 白字支持追加

### E11：蓝底白字按暗字分割，已有同图修复证据

五帧实际蓝底白字图在旧板端输出1AW、1AW、01、0D、01，五组均与旧参考一致。原灰度定位均取得ROI `[21,34,156,81)`；整体反相再定位五帧均无区域，说明不能把反相加在原图采集或定位之前。保留原定位，仅对分割与归一化传flags=2，冻结模型五帧均输出AL67L8。证据：[原板测](../../evidence/blue_polarity/blue_before/summary.json)、[整体反相对照](../../evidence/blue_polarity/blue_probe.json)、[分割归一化反相对照](../../evidence/blue_polarity/blue_seg_invert_probe.json)。

实施改动限于顶层SW5连接和识别子系统极性锁存/任务切换；复用原模块flags[1]，PC参考允许自主flags=0或2。新硬件验证状态见[当前验证](current_validation.md)。目视号码来源及场景条件见[白字支持](white_character_support.md)。

原始接收保存1个不完整组、15,978个接入丢弃字节、CRC候选拒绝0、尾截断0；不得用五个完整一致组抹去接入边界记录。更早的 `before/` 与 `polarity_probe.json` 不是这五帧蓝底白字输入，不能混作本次同图对照。


### E12：v1.1白字实机完成与当前工具状态

white_characters_01已下载RAM，20组自主输出全部AL67L8，120字符、92160像素、4320分数零差异。评分读数来自保存图像人工目视，非用户键入真值，不参与推理。原wire完整保留：1个首部残组、接入discard590 B、末尾truncated2144 B；完整组状态零，bad_captures/publisher_dropped零。用户不方便查看屏幕，未登记本轮目视通过；physical动作已解除VIO，Flash未写。

新实现WNS +0.175 ns、WHS +0.017 ns，首轮通过。[DRC](../../evidence/implementation/white_characters_01/drc.rpt)41项Warning（DPIP8/DPOP1 5/DPOP2 5/DPOR17/PDCN3/RPBF2/RTSTAT1），无严重DRC；[check_timing](../../evidence/implementation/white_characters_01/check_timing.rpt)14项no_input_delay、8项partial_input_delay，新增使用SW5使被观察输入数较v1.0变化。异步输入已有false path，外部FIFO时序仍为原预算。旧synth_ip兼容及路径分段提示保留，未改变约束来掩盖时序失败。

极性修复不重训练CNN，也不改变定位器亮度条件。合成对比度四分之一时输出IL8的离线边界保留在contrast_sensitivity.json，未把反相宣称为任意低对比恢复。

## v1.1 Flash安装追加（2026-11-01）

本次已将white_characters_01写入MX25L3273F并通过Program/Verify；以上旧阶段“Flash未写”的记载保持历史原意。首次启动检查误将Vivado 2025.1的空返回值当作启动失败，尽管日志DONE为HIGH。修正验收脚本后，重新加载匹配VIO，帧计数增加34，错误码0；成功路径没有下载业务BIT。旧4 MiB Flash已完整备份。详见[安装记录](../../evidence/flash_install/installation.json)。本次未进行物理断电重启或屏幕目视确认。
