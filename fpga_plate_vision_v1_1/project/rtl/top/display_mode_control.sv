`timescale 1ns/1ps
// 已同步的实体/虚拟开关统一译码：识别优先于边缘，避免11成为未定义模式。
// 这里只决定业务请求；调度器在帧边界锁存edge，识别子系统自行中止旧任务。
module display_mode_control(input wire edge_switch,recognition_switch,
 output wire edge_requested,recognition_enabled,output wire[1:0]mode);
 assign recognition_enabled=recognition_switch;
 assign edge_requested=edge_switch&&!recognition_switch;
 assign mode=recognition_switch?2'd2:edge_switch?2'd1:2'd0;
endmodule
