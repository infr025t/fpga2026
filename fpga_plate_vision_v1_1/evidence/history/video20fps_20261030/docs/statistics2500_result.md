# 2500帧固定色条RAW统计结果
已完成2500帧，正确2499帧，CRC错误1帧，错误率0.04%。约111.2秒，22.5077fps。
FPGA完整帧CRC逐帧计数；PC记录也连续覆盖1..2500，无漏记。所有帧输入/写屏像素数均为307200，无采集/显示致命错误。
第866帧CRC6823edd0异常，第867帧恢复6df0b9b5，此后至2500正确。错误CRC精确等价前86016像素读到上一FIFO轮次数据、其余正确，与此前旧数据区间错误类型一致。不能据此确定线缆是唯一根因。
当前板上仍为STAT_FRAMES=2500统计诊断版，已自动暂停；复位会再次计数2500帧后停。普通候选bit保存在artifacts/previous_slow；本轮未恢复或上传main。
原始记录：reports/lcd/runtime/stats2500_run01/frames.jsonl、summary.json与bad_frame_analysis.json。bit及hash见reports/final_status.json。
