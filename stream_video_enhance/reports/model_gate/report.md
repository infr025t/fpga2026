# 第15.A节模型质量门槛报告

总结果：**FAIL**；发布profile：无；算法RTL：禁止进入。

登记提交：`cfe857b5fc811c283d5c317006ea5313dc3b70d7`；登记SHA256：`452a24b753dad1c849cbca0a2f004326909ace511edd3904d28a56fd6d3f8280`。
输入归档SHA256：`d208e84909b41c066e0f07428826d7e15ce7b71524db1ea80f7c4c748b7d6c4a`。

调参前固定两个独立主增强图案：细文字和周期4/振幅32纹理；保留集改变文字内容、位置和纹理几何。输入96×128；照片保留登记裁剪尺寸；统一裁边4像素。
噪声每类σ=2/4/8/16、种子0…4；调参/保留使用独立PCG64 seed stream。全部输入、掩膜、64帧序列均已归档并逐数组SHA256校验。

搜索24组共享ε候选，可行候选数：0。固定选择：`{'epsilon': 64, 'T_D': 2, 'T_E': 2, 'G_E': 384, 'L': 16}`，角色：diagnostic_only_no_feasible_tuning_candidate。
若无调参可行项，使用预登记排序第一项作失败诊断；未根据保留集挑选胜者。旧g=1.25/T=4另存非发布对照。

| 检查 | 状态 | 值 |
|---|---|---|
| flat_sigma8_psnr | PASS | 1.7655222345218966 |
| flat_mean_bias | PASS | 0.08068181818183007 |
| clean_line_retention | PASS | 0.9895833333333334 |
| clean_step_far | PASS | 1.0 |
| default_step_overshoot | PASS | 0.0 |
| enhance_step_overshoot | PASS | 0.0 |
| primary_holdout_text_low_clean | FAIL | 0.954965560565542 |
| primary_holdout_texture_p4_a32_clean | FAIL | 0.9375 |
| flat_noise_sigma2 | PASS | 0.566134196590235 |
| flat_noise_sigma4 | PASS | 0.8706044753879147 |
| flat_noise_sigma8 | PASS | 0.9663623254191299 |
| new_clipping | PASS | 0.0 |
| repeated64_exact | PASS | {'RAW': True, 'BASE': True, 'DENOISE': True, 'ENHANCE': True} |
| temporal64_noise | PASS | 0.9635848205867087 |
| tuning_feasible | FAIL | 0 |
| numerical_model | PASS | 见JSON/日志 |
| real_image_classes | PASS | Public photographs supplement text/texture, and are not OV7670 captures; registered masks are contrast diagnostics without clean truth. |
| real_exposure_classes | MISSING | Different-exposure actual photographs/captures with recorded exposure are unavailable. |
| camera_video_evidence | MISSING | Locked-exposure actual-camera 64-frame RAW sequence unavailable; synthetic sequence is simulated. |
| future_rtl_bit_exact | DEFERRED | Only applicable after model gate PASS; no algorithm RTL exists. |

## 全部调参候选

| ε | T_D | T_E | G_E | 主文字/RAW | 主纹理/RAW | 失败项 |
|---|---|---|---|---|---|---|
| 64 | 2 | 2 | 384 | 0.961967 | 0.937500 | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 2 | 2 | 448 | 0.998295 | 0.937500 | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 2 | 4 | 384 | 0.867386 | 0.937500 | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 2 | 4 | 448 | 0.887160 | 0.937500 | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 4 | 2 | 384 | 0.961967 | 0.937500 | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 4 | 2 | 448 | 0.998295 | 0.937500 | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 4 | 4 | 384 | 0.867386 | 0.937500 | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 4 | 4 | 448 | 0.887160 | 0.937500 | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 8 | 2 | 384 | 0.961967 | 0.937500 | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 8 | 2 | 448 | 0.998295 | 0.937500 | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 8 | 4 | 384 | 0.867386 | 0.937500 | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 64 | 8 | 4 | 448 | 0.887160 | 0.937500 | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 256 | 2 | 2 | 384 | 1.081826 | 1.000000 | primary_tuning_texture_p4_a32_clean, flat_noise_sigma8, temporal64_noise |
| 256 | 2 | 2 | 448 | 1.184592 | 1.031250 | primary_tuning_texture_p4_a32_clean, flat_noise_sigma8, temporal64_noise |
| 256 | 2 | 4 | 384 | 0.943186 | 0.906250 | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 256 | 2 | 4 | 448 | 1.023405 | 0.937500 | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 256 | 4 | 2 | 384 | 1.081826 | 1.000000 | primary_tuning_texture_p4_a32_clean, flat_noise_sigma8, temporal64_noise |
| 256 | 4 | 2 | 448 | 1.184592 | 1.031250 | primary_tuning_texture_p4_a32_clean, flat_noise_sigma8, temporal64_noise |
| 256 | 4 | 4 | 384 | 0.943186 | 0.906250 | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 256 | 4 | 4 | 448 | 1.023405 | 0.937500 | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 256 | 8 | 2 | 384 | 1.081826 | 1.000000 | primary_tuning_texture_p4_a32_clean, flat_noise_sigma8, temporal64_noise |
| 256 | 8 | 2 | 448 | 1.184592 | 1.031250 | primary_tuning_texture_p4_a32_clean, flat_noise_sigma8, temporal64_noise |
| 256 | 8 | 4 | 384 | 0.943186 | 0.906250 | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |
| 256 | 8 | 4 | 448 | 1.023405 | 0.937500 | primary_tuning_text_low_clean, primary_tuning_texture_p4_a32_clean |

ε=256也未解决两项目标的权衡（以下仅引用调参数据，不更换保留集诊断参数）：
- T_E=2/G_E=384：纹理/RAW=1.000000；σ8最差空间噪声比=1.103567；时间噪声比=1.100474。纹理未增强，噪声也略过1.1门槛。
- T_E=2/G_E=448：纹理/RAW=1.031250（仍小于1.05）；σ8空间噪声比=1.248829、时间噪声比=1.245006。增加增益加大噪声代价。
- T_E=4可控制噪声，但全部ε=256候选仍未同时达到两项主增强门槛。T_D只控制DENOISE，不改变ENHANCE的失败。

## 保留集定量摘要

| 主案例 | RAW | BASE | DENOISE | ENHANCE | ENHANCE变化 |
|---|---|---|---|---|---|
| holdout_text_low_clean | 32.000000 | 24.421938 | 28.532991 | 30.558898 | -4.503% |
| holdout_texture_p4_a32_clean | 64.000000 | 60.000000 | 60.000000 | 60.000000 | -6.250% |

| σ | RAW平均PSNR | BASE平均PSNR | DENOISE平均PSNR | ENHANCE平均PSNR |
|---|---|---|---|---|
| 2 | 42.008053 | 57.210450 | 49.712401 | 47.063106 |
| 4 | 36.067250 | 47.433144 | 39.723040 | 37.318496 |
| 8 | 30.090857 | 35.660658 | 31.856379 | 30.395605 |
| 16 | 24.065507 | 25.948460 | 24.906699 | 24.423188 |

下表最差对比度包含全部预登记干净/噪声输入，不用于换参数。

| 类别 | 最差输入 | ENHANCE/RAW | 新截断 |
|---|---|---|---|
| line | holdout_line_horizontal_1_s2_n3 | 0.983802 | 0.000000 |
| text | holdout_text_low_clean | 0.954966 | 0.000000 |
| texture | holdout_texture_p8_a16_s4_n0 | 0.908822 | 0.000000 |

## 搜索结束后的探索性诊断

仅将已选诊断配置G_E改为合法上限512，未加入正式候选集，未据此选保留集胜者，结果不参与正式验收或发布。
- holdout_text_low_clean: ENHANCE/RAW=1.020126
- holdout_texture_p4_a32_clean: ENHANCE/RAW=0.937500
主纹理残差在选定ε下接近死区；单独提高增益不能保证恢复被软阈值消去的细节。具体是否调整参数范围或算法，仍须用户决定。

## 四模式与代价

每个输入RAW/BASE/DENOISE/ENHANCE的对比度、相对RAW比例、空间噪声、均值、PSNR（仅合成干净参考）、均值偏移和新增截断见metrics.json的holdout.cases。
零MSE的PSNR用null和psnr_infinite=true表示。全部σ16和5种子均保留。阶跃包含越界幅值、受影响像素数和宽度；edge_profiles.json/PNG保存三个方向剖面。
序列先按固定像素跨64帧取总体标准差，再对固定平坦掩膜取均值；移动与模拟曝光变化另外报告帧差和移动阶跃光晕。它们不冒称真实曝光采集。

## 真实证据边界

focus_latest第一RAW面板有仓库日志支持：真实OV7670石墨十字。frame545为MODE1 Sobel，phase_contact含帧时序故障，回归合成帧均未冒充真实RAW。
scikit-image v0.25.2 camera/text是公开真实照片，并非OV7670拍摄；授权与文件/像素哈希见registration.json和sources/provenance.json。真实图没有虚构干净参考或PSNR。
- Different-exposure actual photographs/captures with recorded exposure are unavailable.
- Locked-exposure actual-camera 64-frame RAW sequence unavailable; synthetic sequence is simulated.
- Actual OV7670 fine text and independent natural texture scenes unavailable; public real photos supplement real-image classes only.

## 最小后续决策

先补采固定曝光/增益的实际平坦、细文字、纹理及不同曝光RAW图和64帧序列；若数值门槛仍失败，按规格第17节由用户决定是否调整公式/参数范围/目标。当前不改阈值、不冻结profile、不编写算法RTL。

## 复现

```powershell
python -m stream_video_enhance.model.evaluate --register
# 审阅并提交registration.json、inputs.npz及生成代码，然后运行
python -m stream_video_enhance.model.evaluate --run
python -m unittest discover -s stream_video_enhance/tests -v
```

质量FAIL/MISSING时--run返回1并保留报告；输入校验/缺登记异常返回2。数值测试日志在numerical_tests.txt。

## 审阅后剖面修正

水平阶跃原图错误地沿中间行采样，所得曲线没有跨边缘。现改为中间列沿输出y取样；垂直和斜边仍沿中间行的输出x取样。斜边横轴不是垂直距离。独立32/224字面阶跃夹具检查三方向、四模式两端平台，先复现水平四模式失败，再通过修正。

登记、输入归档、原24组搜索指标及FAIL结果保持原字节。附注：原real_image_classes的PASS只表示有三张真实图片，并未通过明确类别/区域掩膜证明平坦、文字、纹理覆盖；此项不应解读为覆盖已验证。新一轮须另登记类别和固定掩膜。
