`timescale 1ns/1ps
package core_latency_pkg;
 localparam integer L_MOM=9,L_COEF=20,L_BOX=12,L_REC=3;
 // Arithmetic-stage sum only: the guided wrapper also has intermodule
 // handoff edges. Runtime framing uses valid/coordinates, never this sum.
 localparam integer L_GUIDED_BASE=L_MOM+L_COEF+L_BOX+L_REC+1;
 localparam integer L_GAUSSIAN=4,L_SOBEL=5;
endpackage
