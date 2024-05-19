// xosera_xoseram.sv - Top module for UPduino v3.0 Xosera
//
// vim: set et ts=4 sw=4
//
// Copyright (c) 2020 Xark - https://hackaday.io/Xark
//
// See top-level LICENSE file for license information. (Hint: MIT)

`default_nettype none               // mandatory for Verilog sanity
`timescale 1ns/1ps                  // mandatory to shut up Icarus Verilog

`include "xosera_pkg.sv"

module xosera_xoseram(
            // left side (USB at top)
            input  logic        bus_cs_n,        // m68k bus select (RGB red, UPduino 3.0 needs jumper R28 cut)
            input  logic        bus_rd_nwr,      // m68k bus read/not write (RGB green when output)
            input  logic        bus_bytesel,       // m68k bus byte select (RGB blue when output)
            input  logic [3:0]  bus_reg_num,        // m68k bus regnum 0
            inout  logic [7:0]  bus_data,        // m68k bus regnum 1
            output logic        audio_l,        // m68k bus regnum 2
            output logic        audio_r,        // m68k bus regnum 3
            output logic [3:0]  dv_r,        // audio left output
            output logic [3:0]  dv_g,        // audio left output
            output logic [3:0]  dv_b,        // audio left output
            output logic        dv_hs,        // audio right output (NOTE: this gpio can't be input)
            output logic        dv_vs,        // m68k bus data 0
            output logic        dv_de,        // m68k bus data 1
            output logic        bus_irq_n,        // m68k bus data 2
            output logic        dv_idck,        // m68k bus data 2
            input  logic        clk_12mhz,        // m68k bus data 2
            output logic        spi_ss_n        // m68k bus data 2
       );

assign spi_ss_n = 1'b1;                   // prevent SPI flash interfering with other SPI/FTDI pins

// gpio pin aliases
/* verilator lint_off UNDRIVEN */
logic [3:0] dv_r_int;                   // vga red (4-bit)
logic [3:0] dv_g_int;                   // vga green (4-bits)
logic [3:0] dv_b_int;                   // vga blue (4-bits)
logic       dv_hs_int;                  // vga hsync
logic       dv_vs_int;                  // vga vsync
logic       dv_de_int;                  // DV display enable
logic       bus_intr;                   // interrupt signal
logic       reconfig;                   // set to 1 to force reconfigure of FPGA
logic       reconfig_r;                 // registered signal, to improve timing
logic [1:0] boot_select;                // two bit number for flash configuration to load on reconfigure
logic [1:0] boot_select_r;              // registered signal, to improve timing
/* verilator lint_on UNDRIVEN */

// split tri-state data lines into in/out signals for inside FPGA
logic bus_out_ena;
logic [7:0] bus_data_out;               // bus out from Xosera
logic [7:0] bus_data_out_r;             // registered bus_data_out signal (experimental)
logic [7:0] bus_data_in;                // bus input to Xosera

// only set bus to output if Xosera is selected and read is selected
assign bus_out_ena  = (bus_cs_n == xv::CS_ENABLED && bus_rd_nwr == xv::RnW_READ);

`ifdef SYNTHESIS
// NOTE: Use iCE40 SB_IO primitive to control tri-state properly here
/* verilator lint_off PINMISSING */
SB_IO #(
    .PIN_TYPE(6'b101001)    //PIN_OUTPUT_TRISTATE|PIN_INPUT
) bus_tristate [7:0] (
    .PACKAGE_PIN(bus_data),
    .INPUT_CLK(pclk),
    .OUTPUT_CLK(pclk),
    .OUTPUT_ENABLE(bus_out_ena),
    .D_OUT_0(bus_data_out_r),
    .D_IN_0(bus_data_in)
);
/* verilator lint_on PINMISSING */
`else
// NOTE: Using the registered ("_r") signal may be a win for <posedge pclk> -> async
//        timing on bus_data_out signals (but might cause issues?)
assign bus_data     = bus_out_ena ? bus_data_out_r  : 8'bZ;
assign bus_data_in  = bus_data;
`endif

// update registered signals each clock
always_ff @(posedge pclk) begin
    bus_data_out_r  <= bus_data_out;
    bus_irq_n       <= bus_intr;
    reconfig_r      <= reconfig;
    boot_select_r   <= boot_select;
end

// PLL to derive proper video frequency from 12MHz oscillator (gpio_20 with OSC jumper shorted)
logic pclk;                  // video pixel clock output from PLL block
logic pll_lock;              // indicates when PLL frequency has locked-on

`ifdef SYNTHESIS
/* verilator lint_off PINMISSING */
SB_PLL40_CORE #(
    .DIVR(xv::PLL_DIVR),        // DIVR from video mode
    .DIVF(xv::PLL_DIVF),        // DIVF from video mode
    .DIVQ(xv::PLL_DIVQ),        // DIVQ from video mode
    .FEEDBACK_PATH("SIMPLE"),
    .FILTER_RANGE(3'b001),
    .PLLOUT_SELECT("GENCLK")
) pll_inst(
    .LOCK(pll_lock),        // signal indicates PLL lock
    .RESETB(1'b1),
    .BYPASS(1'b0),
    .REFERENCECLK(clk_12mhz), // input reference clock
    .PLLOUTGLOBAL(pclk)     // PLL output clock (via global buffer)
);
/* verilator lint_on PINMISSING */

`else
// for simulation use 1:1 input clock (and testbench can simulate proper frequency)
assign pll_lock = 1'b1;
assign pclk     = clk_12mhz;
`endif

// video output signals
`ifdef SYNTHESIS
// NOTE: Use SB_IO DDR to help assure clock arrives a bit before signal
//       Also register the other signals.
SB_IO #(
    .PIN_TYPE(6'b010000)   // PIN_OUTPUT_DDR
) dv_clk_sbio(
    .PACKAGE_PIN(dv_idck),
    .OUTPUT_CLK(pclk),
    .D_OUT_0(1'b0),                   // output on rising edge
    .D_OUT_1(1'b1)                    // output on falling edge
);

SB_IO #(
    .PIN_TYPE(6'b010100)   // PIN_OUTPUT_REGISTERED
) dv_signals_sbio [14: 0](
    .PACKAGE_PIN({dv_de, dv_vs,  dv_hs, dv_r, dv_g, dv_b}),
    .OUTPUT_CLK(pclk),
    .D_OUT_0({dv_de_int, dv_vs_int, dv_hs_int, dv_r_int, dv_g_int, dv_b_int}),
);
`else
assign {dv_de, dv_vs,  dv_hs, dv_r, dv_g, dv_b} = {dv_de_int, dv_vs_int, dv_hs_int, dv_r_int, dv_g_int, dv_b_int};
assign dv_idck   = pclk;    // output HDMI clk
`endif

`ifdef SYNTHESIS
SB_WARMBOOT boot(
    .BOOT(reconfig_r),
    .S0(boot_select_r[0]),
    .S1(boot_select_r[1])
);
`else
always @* begin
    if (reconfig_r) begin
        $display("XOSERA REBOOT: To flash config #0x%x", boot_select_r);
        $finish;
    end
end
`endif

// reset logic waits for PLL lock
logic reset;

always_ff @(posedge pclk) begin
    // reset if pll_lock lost
    if (!pll_lock) begin
        reset       <= 1'b1;
    end
    else begin
        reset       <= 1'b0;
    end
end
 
// xosera main module
/* verilator lint_off PINMISSING */
xosera_main xosera_main(
    .red_o(dv_r_int),
    .green_o(dv_g_int),
    .blue_o(dv_b_int),
    .bus_intr_o(bus_intr),
    .vsync_o(dv_vs_int),
    .hsync_o(dv_hs_int),
    .dv_de_o(dv_de_int),
    .bus_cs_n_i(bus_cs_n),
    .bus_rd_nwr_i(bus_rd_nwr),
    .bus_reg_num_i(bus_reg_num),
    .bus_bytesel_i(bus_bytesel),
    .bus_data_i(bus_data_in),
    .bus_data_o(bus_data_out),
    .audio_l_o(audio_l),
    .audio_r_o(audio_r),
    .reconfig_o(reconfig),
    .boot_select_o(boot_select),
    .reset_i(reset),
    .clk(pclk)
);
/* verilator lint_on PINMISSING */
endmodule
