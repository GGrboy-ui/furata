library verilog;
use verilog.vl_types.all;
entity smoke_selftest is
    generic(
        DIV             : integer := 4;
        WIDTH           : integer := 8
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        count           : out    vl_logic_vector;
        tick            : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of DIV : constant is 2;
    attribute mti_svvh_generic_type of WIDTH : constant is 2;
end smoke_selftest;
