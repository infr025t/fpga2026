`timescale 1ns/1ps
package core_latency_pkg;
 // Acceptance edge t -> after-NBA output edge t+L. Verified by stage/core benches.
 localparam integer L_MOM=9,L_COEF=20,L_BOX=12,L_REC=3,L_ENH=7,L_LINK=4,L_ALIGN=0;
 localparam integer L_CORE=L_MOM+L_COEF+L_BOX+L_REC+L_ENH+L_LINK+L_ALIGN;
endpackage
