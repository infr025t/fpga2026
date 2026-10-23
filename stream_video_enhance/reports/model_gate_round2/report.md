# 第15.A节扩大搜索：第二轮独立保留集报告

受控模型门槛：**FAIL**；发布profile：无；算法RTL：禁止进入。

登记提交：`6b6ccc78f0d829b636a236aacc1dee80166db4eb`；登记SHA256：`7ed05a28f3aa5a3aaeb3b5a30e179cffb28662c1f23748b40ed7c73eae41545b`。
输入归档SHA256：`9691656a1336738474000220f04a49703e964c1463707fb39a566a6fba8bc5d6`；执行模型提交：`d36c7c255a8953c371c853e2a174ae7374f095ce`；登记生成模型提交：`90b82771f1af3abf5eb6eaa89578f49d9fcc44da`。

用户于2026-10-23授权保持公式、位宽及RAW+5%阈值，扩至4种ε和G512。首轮reports/model_gate的24项FAIL及归档原样保留；本轮不改写首轮结论。
真实不同曝光和真实固定曝光64帧验证按授权移至相机集成里程碑，当前均DEFERRED、非本轮必选；不称为PASS。受控PASS只允许开展算法RTL。

## 搜索前固定的证据与选择规则

正式候选恰72项：ε16/64/256/1024，T_D2/4/8，T_E2/4，G_E384/448/512，L16；按这些字段升序选择第一个调参可行项。没有可行项才用首项诊断。
调参干净图案保留原定义。新保留集文字为Core VGA/Gain 512/Pixel 2026，起点(7,11)；纹理为(x+2y+1)%period<period/2的斜向条纹，周期4/8、振幅16/32；两项主例固定为文字和周期4振幅32。
两个新主输入逐字节不同于首轮全部二维U8数组与调参主图。所有噪声/时间噪声使用SeedSequence entropy2026102302，按split/pattern/sigma/seed分流；不只移动旧保留图的相位。
平场、细线、阶跃、渐变、棋盘、脉冲、高光及移动阶跃是复用的规范压力图案（REUSED_NOT_NOVEL_HOLDOUT_EVIDENCE），不冒称新增独立保留证据。统一每边裁4像素，输入与掩膜哈希全在registration.json。
72项中调参可行数：0；固定选择：`{'epsilon': 16, 'T_D': 2, 'T_E': 2, 'G_E': 384, 'L': 16}`；角色：diagnostic_only_no_feasible_tuning_candidate。
选择完全基于调参集；新保留集仅评所选一项一次，不另跑旧参数或探索参数，不按保留集排名。

## 必选门槛与延期项

| 检查 | 必选 | 状态 | 值或证据 |
|---|---|---|---|
| flat_sigma8_psnr | 是 | PASS | 1.4948911304358468 |
| flat_mean_bias | 是 | PASS | 0.14393939393940514 |
| clean_line_retention | 是 | PASS | 0.9973958333333334 |
| clean_step_far | 是 | PASS | 1.0 |
| default_step_overshoot | 是 | PASS | 0.0 |
| enhance_step_overshoot | 是 | PASS | 0.0 |
| primary_holdout_text_low_clean | 是 | FAIL | 0.9298255927768597 |
| primary_holdout_texture_p4_a32_clean | 是 | FAIL | 1.0 |
| flat_noise_sigma2 | 是 | PASS | 0.5252193247877779 |
| flat_noise_sigma4 | 是 | PASS | 0.7501729198753309 |
| flat_noise_sigma8 | 是 | PASS | 0.8591164528762827 |
| new_clipping | 是 | PASS | 0.0 |
| repeated64_exact | 是 | PASS | {'RAW': True, 'BASE': True, 'DENOISE': True, 'ENHANCE': True} |
| temporal64_noise | 是 | PASS | 0.8576498250923649 |
| tuning_feasible | 是 | FAIL | 0 |
| numerical_model | 是 | PASS | 见JSON |
| real_image_classes | 是 | PASS | Explicit registered photographic regions and nonempty fixed masks; public photos are not OV7670 captures. No clean photographic reference or PSNR. |
| real_exposure_classes | 否 | DEFERRED | Different-exposure actual photographs/captures with recorded exposure are unavailable. |
| camera_video_evidence | 否 | DEFERRED | Locked-exposure actual-camera 64-frame RAW sequence unavailable; synthetic sequence is simulated. |
| future_rtl_bit_exact | 否 | DEFERRED | Only applicable after model gate PASS; no algorithm RTL exists. |

## 全部72项调参结果

| ε | T_D | T_E | G_E | 文字/RAW | 纹理/RAW | 结果 | 失败项 |
|---|---|---|---|---|---|---|---|
| 16 | 2 | 2 | 384 | 0.933585 | 1.000000 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 16 | 2 | 2 | 448 | 0.937028 | 1.000000 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 16 | 2 | 2 | 512 | 0.939588 | 1.000000 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 16 | 2 | 4 | 384 | 0.921315 | 1.000000 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 16 | 2 | 4 | 448 | 0.921315 | 1.000000 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 16 | 2 | 4 | 512 | 0.921403 | 1.000000 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 16 | 4 | 2 | 384 | 0.933585 | 1.000000 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 16 | 4 | 2 | 448 | 0.937028 | 1.000000 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 16 | 4 | 2 | 512 | 0.939588 | 1.000000 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 16 | 4 | 4 | 384 | 0.921315 | 1.000000 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 16 | 4 | 4 | 448 | 0.921315 | 1.000000 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 16 | 4 | 4 | 512 | 0.921403 | 1.000000 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 16 | 8 | 2 | 384 | 0.933585 | 1.000000 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 16 | 8 | 2 | 448 | 0.937028 | 1.000000 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 16 | 8 | 2 | 512 | 0.939588 | 1.000000 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 16 | 8 | 4 | 384 | 0.921315 | 1.000000 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 16 | 8 | 4 | 448 | 0.921315 | 1.000000 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 16 | 8 | 4 | 512 | 0.921403 | 1.000000 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 2 | 2 | 384 | 0.961967 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 2 | 2 | 448 | 0.998295 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 2 | 2 | 512 | 1.033485 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean, flat_noise_sigma8, temporal64_noise |
| 64 | 2 | 4 | 384 | 0.867386 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 2 | 4 | 448 | 0.887160 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 2 | 4 | 512 | 0.906846 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 4 | 2 | 384 | 0.961967 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 4 | 2 | 448 | 0.998295 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 4 | 2 | 512 | 1.033485 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean, flat_noise_sigma8, temporal64_noise |
| 64 | 4 | 4 | 384 | 0.867386 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 4 | 4 | 448 | 0.887160 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 4 | 4 | 512 | 0.906846 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 8 | 2 | 384 | 0.961967 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 8 | 2 | 448 | 0.998295 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 8 | 2 | 512 | 1.033485 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean, flat_noise_sigma8, temporal64_noise |
| 64 | 8 | 4 | 384 | 0.867386 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 8 | 4 | 448 | 0.887160 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 8 | 4 | 512 | 0.906846 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 256 | 2 | 2 | 384 | 1.081826 | 1.000000 | FAIL | primary_tuning_texture_p4_a32_clean, flat_noise_sigma8, temporal64_noise |
| 256 | 2 | 2 | 448 | 1.184592 | 1.031250 | FAIL | primary_tuning_texture_p4_a32_clean, flat_noise_sigma8, temporal64_noise |
| 256 | 2 | 2 | 512 | 1.287071 | 1.062500 | FAIL | flat_noise_sigma4, flat_noise_sigma8, new_clipping, temporal64_noise |
| 256 | 2 | 4 | 384 | 0.943186 | 0.906250 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 256 | 2 | 4 | 448 | 1.023405 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 256 | 2 | 4 | 512 | 1.102034 | 0.937500 | FAIL | primary_tuning_texture_p4_a32_clean |
| 256 | 4 | 2 | 384 | 1.081826 | 1.000000 | FAIL | primary_tuning_texture_p4_a32_clean, flat_noise_sigma8, temporal64_noise |
| 256 | 4 | 2 | 448 | 1.184592 | 1.031250 | FAIL | primary_tuning_texture_p4_a32_clean, flat_noise_sigma8, temporal64_noise |
| 256 | 4 | 2 | 512 | 1.287071 | 1.062500 | FAIL | flat_noise_sigma4, flat_noise_sigma8, new_clipping, temporal64_noise |
| 256 | 4 | 4 | 384 | 0.943186 | 0.906250 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 256 | 4 | 4 | 448 | 1.023405 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 256 | 4 | 4 | 512 | 1.102034 | 0.937500 | FAIL | primary_tuning_texture_p4_a32_clean |
| 256 | 8 | 2 | 384 | 1.081826 | 1.000000 | FAIL | primary_tuning_texture_p4_a32_clean, flat_noise_sigma8, temporal64_noise |
| 256 | 8 | 2 | 448 | 1.184592 | 1.031250 | FAIL | primary_tuning_texture_p4_a32_clean, flat_noise_sigma8, temporal64_noise |
| 256 | 8 | 2 | 512 | 1.287071 | 1.062500 | FAIL | flat_noise_sigma4, flat_noise_sigma8, new_clipping, temporal64_noise |
| 256 | 8 | 4 | 384 | 0.943186 | 0.906250 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 256 | 8 | 4 | 448 | 1.023405 | 0.937500 | FAIL | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 256 | 8 | 4 | 512 | 1.102034 | 0.937500 | FAIL | primary_tuning_texture_p4_a32_clean |
| 1024 | 2 | 2 | 384 | 1.094914 | 1.156250 | FAIL | enhance_step_overshoot, flat_noise_sigma8, temporal64_noise |
| 1024 | 2 | 2 | 448 | 1.239009 | 1.250000 | FAIL | enhance_step_overshoot, flat_noise_sigma4, flat_noise_sigma8, temporal64_noise |
| 1024 | 2 | 2 | 512 | 1.382080 | 1.375000 | FAIL | enhance_step_overshoot, flat_noise_sigma4, flat_noise_sigma8, temporal64_noise |
| 1024 | 2 | 4 | 384 | 0.994662 | 1.062500 | FAIL | primary_tuning_text_low_clean |
| 1024 | 2 | 4 | 448 | 1.121348 | 1.156250 | FAIL | enhance_step_overshoot |
| 1024 | 2 | 4 | 512 | 1.246890 | 1.250000 | FAIL | enhance_step_overshoot, flat_noise_sigma8, temporal64_noise |
| 1024 | 4 | 2 | 384 | 1.094914 | 1.156250 | FAIL | enhance_step_overshoot, flat_noise_sigma8, temporal64_noise |
| 1024 | 4 | 2 | 448 | 1.239009 | 1.250000 | FAIL | enhance_step_overshoot, flat_noise_sigma4, flat_noise_sigma8, temporal64_noise |
| 1024 | 4 | 2 | 512 | 1.382080 | 1.375000 | FAIL | enhance_step_overshoot, flat_noise_sigma4, flat_noise_sigma8, temporal64_noise |
| 1024 | 4 | 4 | 384 | 0.994662 | 1.062500 | FAIL | primary_tuning_text_low_clean |
| 1024 | 4 | 4 | 448 | 1.121348 | 1.156250 | FAIL | enhance_step_overshoot |
| 1024 | 4 | 4 | 512 | 1.246890 | 1.250000 | FAIL | enhance_step_overshoot, flat_noise_sigma8, temporal64_noise |
| 1024 | 8 | 2 | 384 | 1.094914 | 1.156250 | FAIL | enhance_step_overshoot, flat_noise_sigma8, temporal64_noise |
| 1024 | 8 | 2 | 448 | 1.239009 | 1.250000 | FAIL | enhance_step_overshoot, flat_noise_sigma4, flat_noise_sigma8, temporal64_noise |
| 1024 | 8 | 2 | 512 | 1.382080 | 1.375000 | FAIL | enhance_step_overshoot, flat_noise_sigma4, flat_noise_sigma8, temporal64_noise |
| 1024 | 8 | 4 | 384 | 0.994662 | 1.062500 | FAIL | primary_tuning_text_low_clean |
| 1024 | 8 | 4 | 448 | 1.121348 | 1.156250 | FAIL | enhance_step_overshoot |
| 1024 | 8 | 4 | 512 | 1.246890 | 1.250000 | FAIL | enhance_step_overshoot, flat_noise_sigma8, temporal64_noise |

## 新保留集四模式与代价

| 主案例 | RAW对比度 | BASE | DENOISE | ENHANCE | ENHANCE/RAW |
|---|---|---|---|---|---|
| holdout_text_low_clean | 32.000000 | 29.279897 | 29.642954 | 29.754419 | 0.929826 |
| holdout_texture_p4_a32_clean | 64.000000 | 64.000000 | 64.000000 | 64.000000 | 1.000000 |

| σ | RAW平均PSNR | BASE | DENOISE | ENHANCE |
|---|---|---|---|---|
| 2 | 42.012896 | 52.640273 | 49.291360 | 47.687204 |
| 4 | 36.073941 | 41.550797 | 39.507976 | 38.603242 |
| 8 | 30.098109 | 31.980716 | 31.593000 | 31.420449 |
| 16 | 24.036935 | 24.556777 | 24.551533 | 24.551176 |

最差案例覆盖全部登记干净/加噪细节，不用于换参数。

| 类别 | 最差输入 | ENHANCE/RAW | 新截断比例 |
|---|---|---|---|
| line | holdout_line_horizontal_1_s2_n1 | 0.991913 | 0.000000 |
| text | holdout_text_low_s2_n4 | 0.928307 | 0.000000 |
| texture | holdout_texture_p4_a16_s2_n3 | 0.937369 | 0.000000 |

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
| public_camera_flat_region / flat | BASE | 0.275987 | 2.581062 | 204.747972 | 0.000000 |
| public_camera_flat_region / flat | DENOISE | 0.275987 | 2.581062 | 204.747972 | 0.000000 |
| public_camera_flat_region / flat | ENHANCE | 0.275987 | 2.581062 | 204.747972 | 0.000000 |
| public_camera_texture_region / texture | RAW | 36.917852 | 18.370149 | 150.359444 | 0.000000 |
| public_camera_texture_region / texture | BASE | 34.608151 | 17.659595 | 150.365111 | 0.000000 |
| public_camera_texture_region / texture | DENOISE | 34.750644 | 17.702982 | 150.372407 | 0.000000 |
| public_camera_texture_region / texture | ENHANCE | 34.802289 | 17.719554 | 150.375556 | 0.000000 |
| public_text_text_region / text | RAW | 44.701129 | 23.200877 | 129.026912 | 0.000000 |
| public_text_text_region / text | BASE | 43.449236 | 22.796326 | 129.031111 | 0.000000 |
| public_text_text_region / text | DENOISE | 43.603312 | 22.822869 | 129.028257 | 0.000000 |
| public_text_text_region / text | ENHANCE | 43.668931 | 22.836841 | 129.027522 | 0.000000 |
| ov7670_graphite_text_region / text | RAW | 68.136070 | 32.445313 | 214.270575 | 0.000000 |
| ov7670_graphite_text_region / text | BASE | 67.853462 | 32.293577 | 214.262356 | 0.000000 |
| ov7670_graphite_text_region / text | DENOISE | 67.855496 | 32.293407 | 214.261304 | 0.000000 |
| ov7670_graphite_text_region / text | ENHANCE | 67.856235 | 32.293248 | 214.260701 | 0.000000 |

## 证据边界与后续

- Different-exposure actual photographs/captures with recorded exposure are unavailable.
- Locked-exposure actual-camera 64-frame RAW sequence unavailable; synthetic sequence is simulated.
- Actual OV7670 fine text and independent natural texture scenes unavailable; public real photos supplement real-image classes only.

本轮无算法RTL、综合、布局布线或实板证据。受控门槛通过后执行第16节关键模块/延迟冻结与仿真计划；实际曝光、固定曝光视频及相机细文字/自然纹理仍需相机集成补验。若本轮FAIL，保留全部证据并停止算法RTL，按第17节讨论必要调整。

## 复现

```powershell
python -m stream_video_enhance.model.evaluate --experiment expanded-v2 --register --report-dir stream_video_enhance/reports/model_gate_round2
# 仅用于新空目录；登记文件、输入归档、模型代码先提交，再执行搜索。现有登记不可覆盖。
python -m stream_video_enhance.model.evaluate --run --report-dir stream_video_enhance/reports/model_gate_round2
python -m unittest discover -s stream_video_enhance/tests -v
```

受控必选项全部PASS才返回0和发布可追溯profile；FAIL/MISSING返回1，输入/登记无效返回2。完整执行输出见logs，数值回归见numerical_tests.txt。

## 调参失败的具体权衡（只读已有72项）

以下仅解释已完成的调参数据，不另评保留集、不重选参数、不放宽门槛。T_D固定2；换T_D不改变ENHANCE这些指标。

| ε / T_E / G_E | 文字/RAW | 纹理/RAW | σ8空间噪声比 | 时间噪声比 | 阶跃越界灰度 | 失败项 |
|---|---|---|---|---|---|---|
| 256 / 4 / 512 | 1.102034 | 0.937500 | 1.078839 | 1.071075 | 0.000000 | primary_tuning_texture_p4_a32_clean |
| 1024 / 4 / 384 | 0.994662 | 1.062500 | 0.923081 | 0.918466 | 1.000000 | primary_tuning_text_low_clean |
| 1024 / 4 / 448 | 1.121348 | 1.156250 | 1.061645 | 1.055337 | 3.000000 | enhance_step_overshoot |

ε1024/T_E4/G448同时满足本轮调参增强和噪声目标，但阶跃越界3灰度超过2灰度上限；G384降低光晕却未增强主文字。当前合法离散参数无法同时满足既定全部约束。进一步阈值/参数范围/公式取舍必须按第17节与用户讨论；这些数据不构成通过或发布参数。
