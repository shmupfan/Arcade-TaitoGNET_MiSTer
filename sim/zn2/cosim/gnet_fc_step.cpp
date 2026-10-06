// NVC <-> Verilator co-simulation shim for rtl/gnet/gnet_fc.sv (simulation
// only). NVC's Verilog front end cannot read the M2 SystemVerilog, so the
// VHDL entity sim/zn2/cosim/gnet_fc_cosim.vhd calls gnet_fc_step() through
// VHPIDIRECT once per rising clock edge: inputs are the values just before
// the edge, outputs the values just after it (all gnet_fc outputs used by
// zn2_board are registered). One instance per simulation.
#include "Vgnet_fc.h"
#include "verilated.h"
#include <cstdint>

static Vgnet_fc *top = nullptr;

#ifndef GNET_FC_CLK_HZ
#define GNET_FC_CLK_HZ 33868800
#endif

// CLK_HZ the Verilator model was built with (build_gnet_fc.sh), checked by
// the VHDL wrapper against its generic
extern "C" int32_t gnet_fc_clk_hz() { return GNET_FC_CLK_HZ; }

double sc_time_stamp() { return 0; }   // required by verilated.cpp

extern "C" void gnet_fc_step(const int32_t *in, int32_t *out) {
    if (!top) {
        Verilated::randReset(0);
        top = new Vgnet_fc;
        top->clk = 0;
        top->eval();
    }
    top->rst          = in[0];
    top->jp1          = in[1];
    top->card_present = in[2];
    top->cpu_req      = in[3];
    top->cpu_we       = in[4];
    top->cpu_addr     = (uint32_t)in[5];
    top->cpu_be       = in[6];
    top->cpu_wdata    = (uint32_t)in[7];
    top->fmem_ack     = in[8];
    top->fmem_rdata   = in[9];
    top->cmem_ack     = in[10];
    top->cmem_rdata   = in[11];
    top->meta_we      = in[12];
    top->meta_addr    = in[13];
    top->meta_wdata   = in[14];
    top->key_valid    = in[15];
    top->dirty_raddr  = in[16];
    top->dirty_clear  = in[17];
    top->clk = 1;
    top->eval();
    top->clk = 0;
    top->eval();
    out[0]  = top->cpu_ack;
    out[1]  = (int32_t)top->cpu_rdata;
    out[2]  = top->cpu_hit;
    out[3]  = top->zoom_reset;
    out[4]  = top->wd_reset;
    out[5]  = top->fmem_req;
    out[6]  = top->fmem_we;
    out[7]  = top->fmem_chip;
    out[8]  = top->fmem_addr;
    out[9]  = top->fmem_wdata;
    out[10] = top->flash_busy;
    out[11] = top->cmem_req;
    out[12] = top->cmem_we;
    out[13] = top->cmem_addr;
    out[14] = top->cmem_wdata;
    out[15] = top->dirty_set;
    out[16] = top->dirty_hunk;
    out[17] = top->dirty_rdata;
    out[18] = top->card_reset;
    out[19] = top->win_mismatch;
}
