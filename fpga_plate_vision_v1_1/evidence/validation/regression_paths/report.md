# 历史回归入口迁移修复

本轮只修复脚本输入路径与缺失夹具处理，未修改RTL、PC数学、模型或硬件。旧根`E:/FPGA_Test_Work/plate_autonomous_board_20261101`只读。

## 修改与原因

- `make_auto_vectors.py`和`make_segment_chain_vectors.py`输入改为`evidence/baseline/reports/segmentation_reference/vectors`；原`reports`路径运行报FileNotFoundError，见`before_auto.log`、`before_segment.log`。
- `make_auto_current_vectors.py`改读`evidence/baseline/reports/board_camera_100/frames`；原路径报缺少raw.npy，见`before_current.log`。
- 将完整的54份分割夹具（2,676,947字节，包括已有清单）与旧根逐字节对照，仅补齐缺失文件。完整复制确保保留manifest中其他边界用例的可用性。清单位于`evidence/baseline/segmentation_vectors_sha256.json`。
- `make_norm_chain_vectors.py`明确报告原始输入缺失并非零退出，不覆写冻结向量。该缺失在旧根已经存在，不能算新迁移错误。
- `run_norm_chain_sim.ps1`在缺少原输入时，核验`evidence/baseline/norm_chain_vectors_sha256.json`所列5份历史冻结文件后使用它们，输出“未重新生成”的说明。有原始输入时仍走生成流程。
- 路径审查还发现`evaluate_touching_split.py`会静默跳过迁移后的历史帧目录；仅将该输入根改为`evidence/baseline/reports`。该评估脚本本轮未重新执行，其他外部SCENES路径未改。

## 已执行验证

工作目录为工程根，命令如下：

```powershell
python -B scripts/make_auto_current_vectors.py
python -B scripts/make_segment_chain_vectors.py
python -B scripts/make_norm_chain_vectors.py
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_auto_chain_sim.ps1 -Tag engineering_fixed_roi
```

- current生成通过：7框，参考文本BD12345；见`current_vectors.log`。
- segment chain生成通过：2帧、1536归一化像素、72个有符号分数；见`segment_vectors.log`。
- norm生成按预期退出1并说明原输入缺失；见`norm_original_inputs_missing.log`。runner的冻结文件选择/哈希校验前置段单独执行通过，见`norm_frozen_preflight.log`；没有把它称为norm整链仿真通过。
- 固定ROI自主整链退出0，`logs/engineering_fixed_roi_simulate.log`出现`PASS tb_plate_auto_chain autonomous real workers, full raster, seven characters, blank frame, skipped source frames`。七字符帧elapsed_cycles=15,898,875；空白帧elapsed_cycles=8,463,769。脚本结束时全部已记录源哈希稳定。
- 对本次auto、current、segment生成的16份hex逐值对比旧基线，全部相等；见`generated_vector_comparison.json`。manifest里的源路径属于本次整理工程，因此不要求路径文本与旧清单相等。
- 保留仿真runner引用的TB以及本次相关具体向量/场景输入路径均存在；见`path_audit.json`。此项为路径静态审查，不代表全部runner均重新执行。

归一化前置段验证使用原runner在`$runDir=`之前的内容，仅将`$projectRoot`绑定为已确认的新根后执行；没有启动额外归一化整链仿真。固定ROI仿真展开保留两个未连接端口警告（display_enabled、frame_valid），未更改相关RTL，仿真断言通过。

## 证据边界

新增夹具及冻结向量各有来源路径与SHA256；`source_manifest.json`冻结本轮修改脚本、向量、日志和相关清单。无新增综合、无串口、JTAG或Flash访问。上述结果不替代主任务中的新整机布局布线和实机验证。
