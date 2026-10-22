# 输出提速与FPG1 v3接口约定

2026-10-19第三轮。v1/v2完全保持；v3增加Sobel 1 bit打包与仅定位结果输出。下面是本轮固定接口。

## 输出选择与顶层控制

正常显示页（SW14=0）使用：SW10请求1 bit Sobel；SW11请求仅定位结果，须同时SW2=1；SW12选择快速帧间模式。SW14=1时SW10/11/12仍只作原诊断页控制，新输出请求视为0。所有选项在帧间锁存。

仅结果优先于打包。SW10=1但SW1=0（灰度）时仍输出原8位图像。SW11=1但SW2=0时忽略仅结果请求。打包可以不启用定位，此时没有目标扩展数据。启用定位的完整图仍为v2，只有打包或仅结果实际生效时才使用v3。

顶层新增参数 `FRAME_DELAY=START_DELAY`、`FAST_FRAME_DELAY=0`；复位后的首次采集仍等待START_DELAY，后续等待按本帧锁存的快速选项选择FRAME_DELAY/FAST_FRAME_DELAY。默认所有开关为0时保留历史行为。仅结果模式不写/读输出帧缓存，但仍保留该存储以支持运行时切回图像模式，统计和图像核心都运行至完成。

## v3格式

固定72字节头，magic仍为FPG1、version=3。基础字段与v2相同，但payload_length表示实际传输字节数。宽高保留裁剪图尺寸，供ROI和目标坐标检查。

字节32..69为v2目标数据（flags、threshold、ROI、bbox、area、Sx、Sy、min/max）。字节70改为transport_flags，字节71仍为0。合法transport_flags只有：

| 值 | 含义 | payload_length |
|---|---|---|
| 1 | 1 bit Sobel，无定位数据 | ceil(width*height/8) |
| 5 | 1 bit Sobel，含定位数据 | ceil(width*height/8) |
| 6 | 仅定位结果，无图像 | 0 |

bit0=打包，bit1=仅结果，bit2=含定位。值1时字节32..69必须全0；值5/6时按v2约束检查目标统计。打包模式要求基础mode=1；仅结果可为灰度或Sobel模式。其余组合、字节71非0、长度不符均应拒绝。

像素按连续行优先排列，每8个像素一个字节，最早像素放bit0；最后不足8个时高位补0，行末不单独填充。Sobel的0映射0，255映射1。CRC-16/CCITT-FALSE覆盖header[4:]和**线上打包payload**，CRC小端。接收器解码回每像素0/255，PGM仍保存无损展开图。

仅结果包总长74字节（72头+2CRC）。FrameParser返回 `pixels=b''`、`pixel_format='none'`；保存JSON/CSV，`image_file=null`，不创建PGM。--display更新状态文本，不能把上一次图像冒充当前帧；可以用空白画布显示ROI、框与中心，但必须明确标注仅结果。打包返回展开pixels和 `pixel_format='mono1'`；v1/v2则 `pixel_format='gray8'`，均可正常显示和保存PGM。

JSON/CSV记录实际线上payload_length和pixel_format；v3无定位时不创建target对象。CSV统一平铺字段，保留旧表头文件；v3新schema遇到旧表头时优先写metadata_v3.csv。

## RTL发送器接口

frame_sender追加参数 `OUTPUT_PROTOCOL=0`，末尾追加输入 `pack_edges, features_only`。0时完全忽略新输入，旧测试保持v1/v2；新顶层设置1。实际仅结果条件：OUTPUT_PROTOCOL && TARGET_PROTOCOL && target_enable && features_only；实际打包条件：OUTPUT_PROTOCOL && pack_edges && edge_mode && !实际仅结果。

每次start锁存头长、输出格式、目标状态及全部字段。发送期间改变live模式不得影响包格式、RAM读序和CRC。打包仍从原8位同步RAM顺序读全部像素（用ram_data[7]），每8点发一字节；仅结果直接从头跳到CRC，不扫描RAM。不得改变UART时序或旧原始数据路径。

新增tb_output_transport写output_wire.bin，固定6帧：打包无定位、打包含定位、仅结果有效、仅结果无目标、灰度打包请求回退旧格式、回到v2原始图。尺寸选择非8倍数，检查末尾填充、字段锁存、CRC和切换；额外边界/性能用例可另写文件，不混入这6帧。

新增tb_top_output写top_output_wire.bin，固定5帧：默认旧图、打包含定位、仅结果、切回v2原图、诊断页（输出位忽略）。检查开关帧间锁存、首次START_DELAY与后续FAST_FRAME_DELAY、仅结果期间不访问缓存，回图像时完整重写缓存。更详细测试可独立执行，但上述流帧数固定供runner交叉验证。
