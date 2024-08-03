// bus_interface.sv
//
// vim: set et ts=4 sw=4
//
// Copyright (c) 2020 Xark - https://hackaday.io/Xark
//
// See top-level LICENSE file for license information. (Hint: MIT)
//
`default_nettype none               // mandatory for Verilog sanity
`timescale 1ns/1ps                  // mandatory to shut up Icarus Verilog

`include "xosera_pkg.sv"

module bus_interface(
    // bus interface signals
    input  wire logic         bus_cs_n_i,       // register select strobe
    input  wire logic         bus_rd_nwr_i,     // 0 = write, 1 = read
    input  wire logic  [3:0]  bus_reg_num_i,    // register number
    input  wire logic         bus_bytesel_i,    // 0=even byte, 1=odd byte
    input  wire logic  [7:0]  bus_data_i,       // 8-bit data bus input (broken out from bi-dir data bus)
    output      logic  [7:0]  bus_data_o,       // 8-bit data bus output (broken out from bi-dir data bus)
`ifdef EN_DTACK
    output      logic         bus_dtack_n_o,    // DTACK signal for FPGA
`endif
    // register interface signals
    output      logic         write_l_strobe_o, // strobe for register low write
    output      logic         write_h_strobe_o, // strobe for register high write
    output      logic         read_l_strobe_o,  // strobe for register low read
    output      logic         read_h_strobe_o,  // strobe for register high read
    output      logic  [3:0]  reg_num_o,        // register number read/written
    output      logic  [15:0] bytedata_o,       // byte written to register
    input  wire logic  [15:0] bytedata_i,       // byte read from register
    input  wire logic         rd_ack_i,         // read cycle completed
    input  wire logic         wr_ack_i,         // write cycle completed
    // standard signals
    input  wire logic         clk,              // input clk (should be > 2x faster than bus signals)
    input  wire logic         reset_i           // reset
);

// input synchronizers
logic       cs_n;
logic       cs_n_last;      // previous state to determine edge
logic       rd_nwr;
logic       bytesel;
logic [3:0] reg_num;
byte_t      data;

always_comb begin
    bytedata_o = {data, data};
end

always_ff @(posedge clk) begin
    if (reset_i) begin
        cs_n        <= 1'b0;
        cs_n_last  <= 1'b0;
        rd_nwr      <= 1'b0;
        bytesel     <= 1'b0;
        reg_num     <= 4'b0;
        data        <= 8'b0;
        bus_data_o      <= 8'h00;
        write_l_strobe_o  <= 1'b0;
        write_h_strobe_o  <= 1'b0;
        read_l_strobe_o   <= 1'b0;
        read_h_strobe_o   <= 1'b0;
        reg_num_o       <= 4'h0;
        bus_dtack_n_o   <= xv::DTACK_N_NAK;     // default DTACK to NAK
    end else begin
        cs_n        <= bus_cs_n_i;
        cs_n_last  <= cs_n;
        rd_nwr      <= bus_rd_nwr_i;
        bytesel     <= bus_bytesel_i;
        reg_num     <= bus_reg_num_i;
        data        <= bus_data_i;

        // set outputs
        reg_num_o           <= reg_num;         // output selected register number

        write_l_strobe_o    <= 1'b0;            // clear write low strobe
        write_h_strobe_o    <= 1'b0;            // clear write high strobe
        read_l_strobe_o     <= 1'b0;            // clear read low strobe
        read_h_strobe_o     <= 1'b0;            // clear read high strobe

        // if CS edge (filter out spurious pulse)
        if (cs_n_last == xv::CS_DISABLED && cs_n == xv::CS_ENABLED) begin
            if (rd_nwr == xv::RnW_WRITE) begin
                if (!bytesel) begin
                    write_h_strobe_o  <= 1'b1;        // output write strobe
                end else begin
                    write_l_strobe_o  <= 1'b1;        // output write strobe
                end
            end else begin
                if (!bytesel) begin
                    read_h_strobe_o   <= 1'b1;        // output read strobe
                end else begin
                    read_l_strobe_o   <= 1'b1;        // output read strobe
                end
            end
        end

        // if ack pulse
        if (cs_n == xv::CS_ENABLED) begin
            if (rd_nwr == xv::RnW_WRITE && wr_ack_i) begin
                bus_dtack_n_o <= xv::DTACK_N_ACK;
            end
            if (rd_nwr == xv::RnW_READ && rd_ack_i) begin
                bus_dtack_n_o <= xv::DTACK_N_ACK;
                if (!bytesel) begin
                    bus_data_o  <= bytedata_i[15:8];
                end else begin
                    bus_data_o  <= bytedata_i[7:0];
                end
            end
        end else begin
            bus_dtack_n_o     <= xv::DTACK_N_NAK;     // set DTACK to NAK
        end
    end
end

endmodule
`default_nettype wire               // restore default
