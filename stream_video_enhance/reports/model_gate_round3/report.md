# 第15.A节细增益搜索：第三轮独立保留集报告

受控模型门槛：**PASS**；发布profile：已发布；算法RTL：允许进入后续实施。

登记提交：`747c5da2ef8054748e8ac01ebb1fb9d64d9c3d47`；登记SHA256：`4313e070de338caa2abf3e21c3370814dcbd45420c6752af92628e226cb52c34`。
输入归档SHA256：`270f74a61befab69eb8a373154d442b4e0592137c8bf93987b472e1ac829cae8`；执行模型提交：`747c5da2ef8054748e8ac01ebb1fb9d64d9c3d47`；登记生成模型提交：`f1adeba54c925ccf453141dbec8b2807ec6ee81c`。

用户于2026-10-23授权既有合法范围的软件搜索；本轮仅细化G384…448步长4。公式、位宽、舍入及所有验收阈值保持不变；第一轮24项与第二轮72项FAIL和全部输入/报告字节原样保留。
真实不同曝光和真实固定曝光64帧验证按授权移至相机集成里程碑，当前均DEFERRED、非本轮必选；不称为PASS。受控PASS只允许开展算法RTL。

## 搜索前固定的证据与选择规则

正式候选恰51项：ε1024，T_D2/4/8，T_E4，G_E=list(range(384,449,4))，L16。在全部调参检查PASS的候选中，最大化两项主ENHANCE/RAW对比度比值的最小值；并列时先最低T_D、再最低G_E。没有可行项才用首项诊断。
调参干净图案保留原定义。新保留文字BRAM 2026/Smooth Gain/Video Core，起点(17,9)；纹理(2*x+y+3)%period<period/2，周期4/8、振幅16/32；两项主例固定为文字和周期4振幅32。
两个新主输入逐字节不同于前两轮全部二维U8数组与本轮全部调参图，比较在登记提交前完成。所有噪声/时间噪声使用SeedSequence entropy2026102303，按split/pattern/sigma/seed分流。
平场、细线、阶跃、渐变、棋盘、脉冲、高光及移动阶跃是复用的规范压力图案（REUSED_NOT_NOVEL_HOLDOUT_EVIDENCE），不冒称新增独立保留证据。统一每边裁4像素，输入与掩膜哈希全在registration.json。
51项中调参可行数：15；固定选择：`{'epsilon': 1024, 'T_D': 2, 'T_E': 4, 'G_E': 428, 'L': 16}`；角色：selected_on_tuning。
选择完全基于调参集；新保留集仅评所选一项一次，不另跑旧参数或探索参数，不按保留集排名。

## 必选门槛与延期项

| 检查 | 必选 | 状态 | 值或证据 |
|---|---|---|---|
| flat_sigma8_psnr | 是 | PASS | 1.9056098408504318 |
| flat_mean_bias | 是 | PASS | 0.19640151515150706 |
| clean_line_retention | 是 | PASS | 0.9507639244711875 |
| clean_step_far | 是 | PASS | 1.0 |
| default_step_overshoot | 是 | PASS | 0.0 |
| enhance_step_overshoot | 是 | PASS | 2.0 |
| primary_holdout_text_low_clean | 是 | PASS | 1.0879719748601553 |
| primary_holdout_texture_p4_a32_clean | 是 | PASS | 1.125 |
| flat_noise_sigma2 | 是 | PASS | 0.23120994673173179 |
| flat_noise_sigma4 | 是 | PASS | 0.6474112762156886 |
| flat_noise_sigma8 | 是 | PASS | 1.018570952149521 |
| new_clipping | 是 | PASS | 0.0001893939393939394 |
| repeated64_exact | 是 | PASS | {'RAW': True, 'BASE': True, 'DENOISE': True, 'ENHANCE': True} |
| temporal64_noise | 是 | PASS | 1.0124511359950088 |
| tuning_feasible | 是 | PASS | 15 |
| numerical_model | 是 | PASS | 见JSON |
| real_image_classes | 是 | PASS | Explicit registered photographic regions and nonempty fixed masks; public photos are not OV7670 captures. No clean photographic reference or PSNR. |
| real_exposure_classes | 否 | DEFERRED | Different-exposure actual photographs/captures with recorded exposure are unavailable. |
| camera_video_evidence | 否 | DEFERRED | Locked-exposure actual-camera 64-frame RAW sequence unavailable; synthetic sequence is simulated. |
| future_rtl_bit_exact | 否 | DEFERRED | Only applicable after model gate PASS; no algorithm RTL exists. |

## 全部51项调参结果

| ε | T_D | T_E | G_E | 文字/RAW | 纹理/RAW | 结果 | 失败项 |
|---|---|---|---|---|---|---|---|
| 1024 | 2 | 4 | 384 | 0.994662 | 1.062500 | FAIL | primary_tuning_text_low_clean |
| 1024 | 2 | 4 | 388 | 1.002594 | 1.062500 | FAIL | primary_tuning_text_low_clean |
| 1024 | 2 | 4 | 392 | 1.009864 | 1.062500 | FAIL | primary_tuning_text_low_clean |
| 1024 | 2 | 4 | 396 | 1.018768 | 1.062500 | FAIL | primary_tuning_text_low_clean |
| 1024 | 2 | 4 | 400 | 1.026679 | 1.093750 | FAIL | primary_tuning_text_low_clean |
| 1024 | 2 | 4 | 404 | 1.034216 | 1.093750 | FAIL | primary_tuning_text_low_clean |
| 1024 | 2 | 4 | 408 | 1.040473 | 1.093750 | FAIL | primary_tuning_text_low_clean |
| 1024 | 2 | 4 | 412 | 1.050523 | 1.093750 | PASS | 无 |
| 1024 | 2 | 4 | 416 | 1.058081 | 1.093750 | PASS | 无 |
| 1024 | 2 | 4 | 420 | 1.066722 | 1.093750 | PASS | 无 |
| 1024 | 2 | 4 | 424 | 1.072624 | 1.125000 | PASS | 无 |
| 1024 | 2 | 4 | 428 | 1.082171 | 1.125000 | PASS | 无 |
| 1024 | 2 | 4 | 432 | 1.089332 | 1.125000 | FAIL | enhance_step_overshoot |
| 1024 | 2 | 4 | 436 | 1.098034 | 1.125000 | FAIL | enhance_step_overshoot |
| 1024 | 2 | 4 | 440 | 1.104397 | 1.125000 | FAIL | enhance_step_overshoot |
| 1024 | 2 | 4 | 444 | 1.113544 | 1.156250 | FAIL | enhance_step_overshoot |
| 1024 | 2 | 4 | 448 | 1.121348 | 1.156250 | FAIL | enhance_step_overshoot |
| 1024 | 4 | 4 | 384 | 0.994662 | 1.062500 | FAIL | primary_tuning_text_low_clean |
| 1024 | 4 | 4 | 388 | 1.002594 | 1.062500 | FAIL | primary_tuning_text_low_clean |
| 1024 | 4 | 4 | 392 | 1.009864 | 1.062500 | FAIL | primary_tuning_text_low_clean |
| 1024 | 4 | 4 | 396 | 1.018768 | 1.062500 | FAIL | primary_tuning_text_low_clean |
| 1024 | 4 | 4 | 400 | 1.026679 | 1.093750 | FAIL | primary_tuning_text_low_clean |
| 1024 | 4 | 4 | 404 | 1.034216 | 1.093750 | FAIL | primary_tuning_text_low_clean |
| 1024 | 4 | 4 | 408 | 1.040473 | 1.093750 | FAIL | primary_tuning_text_low_clean |
| 1024 | 4 | 4 | 412 | 1.050523 | 1.093750 | PASS | 无 |
| 1024 | 4 | 4 | 416 | 1.058081 | 1.093750 | PASS | 无 |
| 1024 | 4 | 4 | 420 | 1.066722 | 1.093750 | PASS | 无 |
| 1024 | 4 | 4 | 424 | 1.072624 | 1.125000 | PASS | 无 |
| 1024 | 4 | 4 | 428 | 1.082171 | 1.125000 | PASS | 无 |
| 1024 | 4 | 4 | 432 | 1.089332 | 1.125000 | FAIL | enhance_step_overshoot |
| 1024 | 4 | 4 | 436 | 1.098034 | 1.125000 | FAIL | enhance_step_overshoot |
| 1024 | 4 | 4 | 440 | 1.104397 | 1.125000 | FAIL | enhance_step_overshoot |
| 1024 | 4 | 4 | 444 | 1.113544 | 1.156250 | FAIL | enhance_step_overshoot |
| 1024 | 4 | 4 | 448 | 1.121348 | 1.156250 | FAIL | enhance_step_overshoot |
| 1024 | 8 | 4 | 384 | 0.994662 | 1.062500 | FAIL | primary_tuning_text_low_clean |
| 1024 | 8 | 4 | 388 | 1.002594 | 1.062500 | FAIL | primary_tuning_text_low_clean |
| 1024 | 8 | 4 | 392 | 1.009864 | 1.062500 | FAIL | primary_tuning_text_low_clean |
| 1024 | 8 | 4 | 396 | 1.018768 | 1.062500 | FAIL | primary_tuning_text_low_clean |
| 1024 | 8 | 4 | 400 | 1.026679 | 1.093750 | FAIL | primary_tuning_text_low_clean |
| 1024 | 8 | 4 | 404 | 1.034216 | 1.093750 | FAIL | primary_tuning_text_low_clean |
| 1024 | 8 | 4 | 408 | 1.040473 | 1.093750 | FAIL | primary_tuning_text_low_clean |
| 1024 | 8 | 4 | 412 | 1.050523 | 1.093750 | PASS | 无 |
| 1024 | 8 | 4 | 416 | 1.058081 | 1.093750 | PASS | 无 |
| 1024 | 8 | 4 | 420 | 1.066722 | 1.093750 | PASS | 无 |
| 1024 | 8 | 4 | 424 | 1.072624 | 1.125000 | PASS | 无 |
| 1024 | 8 | 4 | 428 | 1.082171 | 1.125000 | PASS | 无 |
| 1024 | 8 | 4 | 432 | 1.089332 | 1.125000 | FAIL | enhance_step_overshoot |
| 1024 | 8 | 4 | 436 | 1.098034 | 1.125000 | FAIL | enhance_step_overshoot |
| 1024 | 8 | 4 | 440 | 1.104397 | 1.125000 | FAIL | enhance_step_overshoot |
| 1024 | 8 | 4 | 444 | 1.113544 | 1.156250 | FAIL | enhance_step_overshoot |
| 1024 | 8 | 4 | 448 | 1.121348 | 1.156250 | FAIL | enhance_step_overshoot |

## 新保留集四模式与代价

| 主案例 | RAW对比度 | BASE | DENOISE | ENHANCE | ENHANCE/RAW |
|---|---|---|---|---|---|
| holdout_text_low_clean | 32.000000 | 7.632454 | 26.220456 | 34.815103 | 1.087972 |
| holdout_texture_p4_a32_clean | 64.000000 | 32.000000 | 60.000000 | 72.000000 | 1.125000 |

| σ | RAW平均PSNR | BASE | DENOISE | ENHANCE |
|---|---|---|---|---|
| 2 | 42.026852 | 59.826049 | 49.831320 | 55.131965 |
| 4 | 36.055172 | 52.034213 | 39.714137 | 39.973673 |
| 8 | 30.063542 | 45.779890 | 31.969152 | 29.933904 |
| 16 | 24.066790 | 35.816434 | 25.971099 | 23.420514 |

最差案例覆盖全部登记干净/加噪细节，不用于换参数。

| 类别 | 最差输入 | ENHANCE/RAW | 新截断比例 |
|---|---|---|---|
| line | holdout_line_vertical_1_s2_n2 | 0.978669 | 0.000000 |
| text | holdout_text_low_s16_n4 | 1.036364 | 0.000000 |
| texture | holdout_texture_p4_a16_s16_n3 | 1.055503 | 0.000000 |

各模式完整对比度/噪声/偏移/截断在metrics.json。PSNR只用于已知合成干净参考；零MSE用null和psnr_infinite表示。σ16作为压力测试保留全部5种子。
阶跃JSON含越界幅值、像素数、垂直宽度；PNG和edge_profiles.json含三方向剖面。水平边沿中间列沿y采样；垂直/斜边沿中间行沿x采样；斜边图横轴不是垂直距离。
64帧的噪声指标先逐像素沿时间取总体标准差、再在固定平场掩膜平均；移动/模拟曝光序列另报帧差与移动光晕，未冒充真实曝光。

## 真实照片固定区域

公开camera.png登记裁剪(0,16,512,496)，sky原坐标(0,0,130,65)对应登记(0,0,130,49)；grass原坐标(350,300,500,480)对应登记(350,284,500,464)。前者为flat、后者texture；text.png为printed text；实际OV7670石墨图为纸面/石墨笔画text补充。
flat区域按横向两半定义固定掩膜，其余区域以原始灰度的0.3/0.7分位定义背景/前景；全部mask搜索前固定并登记，gate比较flat/text/texture类别集合和有效非空mask，不按照片文件数。
真实图不假设干净参考、不计算PSNR；下面只报告固定区域的观测统计。来源/授权/源字节哈希在sources/provenance.json及registration.json；公开照片不是本板摄像头采集。

| 区域/类 | 模式 | 对比度 | 空间标准差 | 均值 | 新截断 |
|---|---|---|---|---|---|
| public_camera_flat_region / flat | RAW | 0.240280 | 2.632697 | 204.736155 | 0.000000 |
| public_camera_flat_region / flat | BASE | 0.279978 | 2.580543 | 204.744092 | 0.000000 |
| public_camera_flat_region / flat | DENOISE | 0.279978 | 2.580543 | 204.744092 | 0.000000 |
| public_camera_flat_region / flat | ENHANCE | 0.279978 | 2.580543 | 204.744092 | 0.000000 |
| public_camera_texture_region / texture | RAW | 36.917852 | 18.370149 | 150.359444 | 0.000000 |
| public_camera_texture_region / texture | BASE | 15.688560 | 11.712106 | 150.378630 | 0.000000 |
| public_camera_texture_region / texture | DENOISE | 31.983684 | 16.526509 | 150.329852 | 0.000000 |
| public_camera_texture_region / texture | ENHANCE | 37.724376 | 19.195633 | 150.379000 | 0.002259 |
| public_text_text_region / text | RAW | 44.701129 | 23.200877 | 129.026912 | 0.000000 |
| public_text_text_region / text | BASE | 36.369941 | 18.850456 | 129.044762 | 0.000000 |
| public_text_text_region / text | DENOISE | 42.552721 | 22.017112 | 128.995385 | 0.000000 |
| public_text_text_region / text | ENHANCE | 44.642129 | 23.735572 | 128.650125 | 0.000000 |
| ov7670_graphite_text_region / text | RAW | 68.136070 | 32.445313 | 214.270575 | 0.000000 |
| ov7670_graphite_text_region / text | BASE | 65.998645 | 31.073527 | 214.263675 | 0.000000 |
| ov7670_graphite_text_region / text | DENOISE | 67.513894 | 32.027809 | 214.218878 | 0.000000 |
| ov7670_graphite_text_region / text | ENHANCE | 67.945179 | 32.547302 | 214.135470 | 0.000000 |

## 证据边界与后续

- Different-exposure actual photographs/captures with recorded exposure are unavailable.
- Locked-exposure actual-camera 64-frame RAW sequence unavailable; synthetic sequence is simulated.
- Actual OV7670 fine text and independent natural texture scenes unavailable; public real photos supplement real-image classes only.

本轮无算法RTL、综合、布局布线或实板证据。受控门槛通过后执行第16节关键模块/延迟冻结与仿真计划；实际曝光、固定曝光视频及相机细文字/自然纹理仍需相机集成补验。若本轮FAIL，保留全部证据并停止算法RTL，按第17节讨论必要调整。

## 复现

```powershell
python -m stream_video_enhance.model.evaluate --experiment finegain-v3 --register --report-dir stream_video_enhance/reports/model_gate_round3
# 仅用于新空目录；登记文件、输入归档、模型代码先提交，再执行搜索。现有登记不可覆盖。
python -m stream_video_enhance.model.evaluate --run --report-dir stream_video_enhance/reports/model_gate_round3
python -m unittest discover -s stream_video_enhance/tests -v
```

受控必选项全部PASS才返回0和发布可追溯profile；FAIL/MISSING返回1，输入/登记无效返回2。完整执行输出见logs，数值回归见numerical_tests.txt。
