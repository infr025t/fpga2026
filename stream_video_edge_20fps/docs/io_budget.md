# Input timing budget correction
RCLK rise -> IO sample enable is30ns, with all CPU arithmetic still100MHz.
Budget: at most23ns for output/board/FIFO access/return, at most5ns FPGA input path, at least2ns remaining. AL422 tAC<=15ns, tOH>=4ns. Actual next change is next RCLK(+60ns)+hold, not the next10ns CPU edge.
Vivado UG903 states that max_delay -datapath_only starting at an input INCLUDES set_input_delay. Therefore28ns is the combined exception budget; the first5ns total constraint double-counted23ns external and was impossible. Removing the explicit same-edge min_delay avoids a fictitious hold fix on a CE-disabled edge. No core clock period is relaxed.
This is an assumed external flight-time budget on existing wires, to be functionally checked by known sensor-pattern CRC. No oscilloscope waveform guarantee is claimed.

UG912 IOBDELAY NONE is explicitly applied to camera inputs to avoid the default fixed ZHOLD input element (~6.7ns at slow corner). This is a physical route change, not relaxing the28ns budget. Build roi_x6 still had default ZHOLD and failed by2.961ns; no failed build was programmed.
Sources: https://docs.amd.com/r/2023.1-English/ug912-vivado-properties/IOBDELAY and https://docs.amd.com/r/2023.1-English/ug903-vivado-using-constraints/Consequences-of-Setting-Maximum-Delay-or-Minimum-Delay-Constraints-on-a-Path
