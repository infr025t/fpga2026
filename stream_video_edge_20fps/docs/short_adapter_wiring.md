# 10cm洞洞板转接头接线对照
用户当前计划：通用洞洞板转接头+10cm杜邦线，原先多根GND分别接Basys3不同接口。接受这套接法作为对照，不宣称控制阻抗或保证高速稳定。

官方Basys3 Rev.C原理图：JA/JB/JC物理5、11均接同一板内GND；物理6、12为VCC3V3。多根模块地分别接不同Pmod GND本来就共地，不需要收成单根地线。物理引脚编号不能混用Verilog JA[]/JC[]数组编号。
建议保持LCD原接法，尤其背光/供电回流不经摄像头单根细地线串回。相机/转接板GND做短粗连续汇流线，保留JA侧数据回流GND，再让JC侧GND伴随JC8->RCK（JC5或JC11物理GND）到相机GND汇流点。RCK与这根GND紧靠或轻绞，不留长分叉/观察支路。所有相机信号总路径尽量短，含洞洞板跨线，不是只量杜邦线标称10cm。数据保持既有D0..D7对应，引脚/程序不变。
洞洞板本身不提供完整地平面，仍有寄生参数；用短直连接、明确GND汇流、不交叉缠绕即可作为当前单变量接线对照。上电前断电检查3V3/GND与相邻信号是否误连。

额外已核实且后续不得忽略：Basys3 Rev.C原理图中JA/JB/JC信号均有200Ω串联电阻（JC8对应R8），不能未经核对就把JB称作无电阻高速Pmod，或盲目再加终端电阻。JXADC没有同样200Ω串阻但当前8线已用于LCD，不能随意换RCK而不处理引脚冲突。本轮先保持映射不变缩线；目前未测实际边沿，200Ω+负载对RC时间常数可能有影响但不是已确认根因。
来源：https://digilent.com/reference/_media/basys3:basys3_sch.pdf （Rev.C.0，第1页PMOD/I/O）
https://digilent.com/reference/_media/reference/programmable-logic/basys-3/basys3_rm.pdf （Rev.C手册Pmod章节）
